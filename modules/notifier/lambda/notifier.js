const https = require('https');
const AWS = require('aws-sdk');
const ssm = new AWS.SSM({ apiVersion: '2014-11-06', region: 'us-east-1' });

async function getBitBucketPRStatus(username, password, pr_id) {
  const uri = encodeURI(`/2.0/repositories/${process.env.SOURCE_REPOSITORY}/pullrequests/${pr_id}`);
  const auth = "Basic " + Buffer.from(username + ":" + password).toString("base64");
  const options = {
    hostname: 'api.bitbucket.org',
    port: 443,
    path: uri,
    method: 'GET',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': auth
    },
  };
  const body = await new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = '';

      res.on("data", (chunk) => {
        data += chunk;
      });

      res.on("end", () => {
        resolve(data);
      });
    });

    req.on("error", (error) => {
      reject(error);
    });

    req.end();
  });
  return body;
}

async function getSSMParam(key, withDecryption, defaultValue = null) {
  var params = {
    Name: `${key}`,
    WithDecryption: withDecryption
  };
  try {
    const { Parameter } = await ssm.getParameter(params).promise();
    return Parameter?.Value ?? defaultValue;
  } catch (e) {
    console.error(e);
    return defaultValue;
  }
}

async function sendTeamsNotification(APP_NAME, ENV_NAME, AUTHOR, MERGED_BY, PR_URL, MERGE_COMMIT, TEAMS_HOOK, TRIBE_NAME) {
  ENV_NAME = (ENV_NAME.toLowerCase() == "prod") ? "Production" : ENV_NAME;

  const data = JSON.stringify({
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "16d700",
    "summary": `${APP_NAME} Deploy to ${ENV_NAME} Done`,
    "sections": [{
      "activityTitle": `${APP_NAME} Deploy to ${ENV_NAME}`,
      "activitySubtitle": `${APP_NAME} of Tribe ${TRIBE_NAME}`,
      "activityImage": "",
      "facts": [{
        "name": "URL",
        "value": `[Bitbucket PR](${PR_URL})`
      },
      {
        "name": "Service Name",
        "value": `${APP_NAME}`
      },
      {
        "name": "Commit Id",
        "value": `${MERGE_COMMIT}`
      },
      {
        "name": "Author",
        "value": `${AUTHOR}`
      },
      {
        "name": "Merged By",
        "value": `${MERGED_BY}`
      }],
      "markdown": true
    }]
  });

  const options = {
    hostname: 'tolunaonline.webhook.office.com',
    path: TEAMS_HOOK.trim(),
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
  };

  console.log(`Sending Teams Notification for ${APP_NAME} to ${ENV_NAME}: ${data}`);

  const req = https.request(options, res => {
    let responseData = '';
    console.log(`Response status for ${APP_NAME}: ${res.statusCode}`);

    res.on('data', d => {
      responseData += d;
    });

    res.on('end', () => {
      console.log(`Response data for ${APP_NAME}: ${responseData}`);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        // Handle successful response here (optional)
      } else {
        console.error(`Request failed with status code ${res.statusCode}: ${responseData}`);
      }
    });
  });

  req.on('error', (error) => {
    console.error('Error sending Teams notification:', error);
  });

  req.write(data);
  req.end();

  // Added await to wait for the request to complete before continuing the loop
  return new Promise((resolve, reject) => {
    req.on('close', () => {
      resolve();
    });
  });
}

exports.handler = async (event) => {
  console.log(event)
  const ENV_NAME = event.ENV_NAME;
  const HOOK_ID = (ENV_NAME.toLowerCase() == "prod") ? '/infra/teams_notification_webhook' : '/infra/non_prod/teams_notification_webhook'
  const username = await getSSMParam('/app/bb_user', true);
  const password = await getSSMParam('/app/bb_app_pass', true);
  const TEAMS_WEBHOOK_LIST = await getSSMParam(HOOK_ID, true);
  const TRIBE_NAME = await getSSMParam('/infra/tribe', true, "(Tribe is undefind, please add tribe name to ssm parameter '/infra/tribe')");
  const pr_id = event.CODEBUILD_WEBHOOK_TRIGGER.replaceAll("pr/", "");
  const bb_pr = await getBitBucketPRStatus(username, password, pr_id);
  const bb_payload = JSON.parse(bb_pr)
  const AUTHOR = bb_payload.author.display_name;
  const MERGED_BY = bb_payload.closed_by.display_name;
  const MERGE_COMMIT = bb_payload.merge_commit.hash;
  const PR_URL = bb_payload.links.html.href;
  const APP_NAME = process.env.APP_NAME.charAt(0).toUpperCase() + process.env.APP_NAME.slice(1);
  const TEAMS_WEBHOOKS = TEAMS_WEBHOOK_LIST.split(',');
  const NOTIFICATIONS = TEAMS_WEBHOOKS.map(async (val) => {
    const notification = await sendTeamsNotification(APP_NAME, ENV_NAME, AUTHOR, MERGED_BY, PR_URL, MERGE_COMMIT, val, TRIBE_NAME)
  })
  await Promise.all(NOTIFICATIONS);
};