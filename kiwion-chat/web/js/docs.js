// Kiwion API docs: theme, live base URL and syntax highlighting.
(function () {
  var dark = window.matchMedia && matchMedia("(prefers-color-scheme: dark)").matches;
  document.documentElement.dataset.theme = dark ? "dark" : "light";
  document.getElementById("hljs-theme").href = dark ? "/vendor/hljs-dark.css" : "/vendor/hljs-light.css";
  var origin = location.origin;
  document.getElementById("base").textContent = origin;
  document.querySelectorAll("pre code").forEach(function (el) {
    el.textContent = el.textContent.split("https://your-domain").join(origin);
    if (window.hljs) window.hljs.highlightElement(el);
  });
  fetch("/api/config/public").then(function (r) { return r.json(); }).then(function (c) {
    document.getElementById("mname").textContent = c.model;
    document.querySelectorAll(".mid").forEach(function (el) { el.textContent = c.model_id; });
  }).catch(function () {});
})();
