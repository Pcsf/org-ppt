// Renders a deck's math to HTML so the exported file needs no runtime.
//
// Reads {"items":[{"tex":"…","display":true}]} on stdin and writes
// {"html":["…"]} on stdout, or {"error":"…"} if KaTeX could not be loaded.
// Invoked once per export by org-ppt.el; see `org-ppt--render-math-queue'.

"use strict";

const path = require("path");

function main(input) {
  let katex;
  try {
    katex = require(path.join(__dirname, "katex.min.js"));
  } catch (e) {
    return { error: "cannot load katex.min.js: " + e.message };
  }
  const items = (JSON.parse(input) || {}).items || [];
  // throwOnError keeps one bad formula from failing the whole export; KaTeX
  // renders it in the error colour instead, exactly as the runtime would.
  const html = items.map((item) =>
    katex.renderToString(String(item.tex), {
      displayMode: Boolean(item.display),
      throwOnError: false,
      errorColor: "#B4232C",
    }),
  );
  return { html };
}

let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => (input += chunk));
process.stdin.on("end", () => {
  let result;
  try {
    result = main(input);
  } catch (e) {
    result = { error: e.message };
  }
  process.stdout.write(JSON.stringify(result));
});
