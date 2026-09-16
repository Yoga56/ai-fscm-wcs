/* Writes the initial mock data (one brief for the slide scenario). Run: npm run mock:data */
"use strict";

const fs = require("fs");
const path = require("path");
const E = require("./engine/engine");
const O = require("./engine/odata");

const out = path.join(__dirname, "data", "generated");
fs.mkdirSync(out, { recursive: true });

const rows = O.snapshot(E.build(E.demoInput()), "b0000001-0000-4000-8000-000000000001");
const write = (name, data) => fs.writeFileSync(path.join(out, `${name}.json`), JSON.stringify(data, null, 2));

write("Brief", [rows.Brief]);
write("RunwayDay", rows.RunwayDay);
write("Risk", rows.Risk);
write("TradeOff", rows.TradeOff);
write("ActionDraft", []);

console.log(`mock data: 1 brief, ${rows.RunwayDay.length} days, ${rows.Risk.length} risks, ${rows.TradeOff.length} advice rows`);
