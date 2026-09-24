/* eslint-env browser */
const query = document.querySelector("#query"),
  status = document.querySelector("#search-status"),
  results = document.querySelector("#results");
let index;
fetch(new URL("search-index.json", document.currentScript.src))
  .then((r) => {
    if (!r.ok) throw Error("unavailable");
    return r.json();
  })
  .then((v) => {
    if (!Array.isArray(v.pages)) throw Error("invalid index");
    index = v;
    run();
  })
  .catch(() => {
    status.textContent =
      "검색 자료를 불러오지 못했습니다. 페이지 탐색 메뉴를 이용하세요.";
  });
query.addEventListener("input", run);
function run() {
  results.replaceChildren();
  if (!index) return;
  const q = query.value.trim().toLocaleLowerCase();
  if (!q) {
    status.textContent = "검색어를 입력해 필요한 내용을 찾으세요.";
    return;
  }
  const matches = index.pages.filter((p) =>
    (p.title + " " + p.summary + " " + p.body).toLocaleLowerCase().includes(q),
  );
  status.textContent = matches.length
    ? matches.length + "개 페이지를 찾았습니다."
    : "검색 결과가 없습니다. 다른 단어를 입력하세요.";
  for (const p of matches) {
    const li = document.createElement("li"),
      a = document.createElement("a"),
      snippet = document.createElement("p");
    a.href = p.url;
    a.textContent = p.title;
    const plain = p.body.replace(/[#*`]/g, "").replace(/\s+/g, " "),
      at = plain.toLocaleLowerCase().indexOf(q),
      start = Math.max(0, at - 25);
    snippet.textContent =
      (start ? "…" : "") +
      plain.slice(start, start + 105) +
      (plain.length > start + 105 ? "…" : "");
    li.append(a, snippet);
    results.append(li);
  }
}
const menu = document.querySelector(".menu"),
  narrow = window.matchMedia("(max-width: 760px)");
function syncMenu() {
  menu.open = !narrow.matches;
}
syncMenu();
narrow.addEventListener("change", syncMenu);
