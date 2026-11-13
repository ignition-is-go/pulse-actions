const fs = require('node:fs');
fs.appendFileSync(process.env.GITHUB_STATE, `fixture=${process.env.INPUT_PATH}\n`);
