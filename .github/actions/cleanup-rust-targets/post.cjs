const fs = require('node:fs');
const path = require('node:path');

function cleanup(root, targets) {
  const checkout = fs.realpathSync(root);
  for (const target of targets) {
    if (!fs.existsSync(target)) continue;
    const resolved = fs.realpathSync(target);
    const relative = path.relative(checkout, resolved);
    // Shared or external target directories are not owned by this checkout.
    if (!relative || relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
      console.log(`Keeping target outside the checkout: ${target}`);
      continue;
    }
    fs.rmSync(target, { recursive: true, force: true });
    console.log(`Removed local Cargo target: ${target}`);
  }
}

if (require.main === module) {
  cleanup(process.env.GITHUB_WORKSPACE, JSON.parse(process.env.STATE_targets));
}
module.exports = { cleanup };
