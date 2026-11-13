import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const env = {...process.env};
// Some parent shells enable DEBUG globally; the CLI otherwise logs the whole
// inherited environment. Keep test output free of environment/credential dumps.
delete env.DEBUG;
env.FIREBASE_CLI_DISABLE_UPDATE_CHECK = 'true';
const result = spawnSync(process.execPath, [fileURLToPath(new URL('./node_modules/firebase-tools/lib/bin/firebase.js', import.meta.url)),
  'emulators:exec', '--project', 'demo-onepoint-security', '--config', '../firebase.json', '--only', 'firestore,storage', 'node --test rules.test.mjs'], {env, stdio:'inherit'});
process.exit(result.status ?? 1);
