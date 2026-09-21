/* Section bar: shows which section you are reading, and closes the section list after a choice.
 * pisg writes <nav id="pisg-nav"><details>...</details></nav>. Without this script the list still
 * opens and every link still works; this only adds the "you are here" label. */
(function () {
  "use strict";
  var nav = document.getElementById("pisg-nav");
  if (!nav) return;
  var menu = nav.querySelector("details");
  var current = document.getElementById("nav-current");
  // Both lists (the dropdown and the menu down the left) carry the same links: one target per section.
  var links = Array.prototype.slice.call(nav.querySelectorAll(".nav-list a"));
  var all = Array.prototype.slice.call(nav.querySelectorAll(".nav-list a, .nav-side-list a"));
  var targets = links.map(function (a) { return document.getElementById(a.getAttribute("href").slice(1)); });
  var active = -1, ticking = false;

  function setActive(i) {
    if (i === active) return;
    active = i;
    all.forEach(function (a) {
      var on = links[i] && a.getAttribute("href") === links[i].getAttribute("href");
      a.classList.toggle("active", !!on);
      if (on) a.setAttribute("aria-current", "true"); else a.removeAttribute("aria-current");
    });
    if (current && links[i]) current.textContent = links[i].textContent;
  }

  function update() {
    ticking = false;
    var side = window.getComputedStyle(nav).position === "fixed";           // the menu down the left takes no height
    var line = (side ? 0 : nav.offsetHeight) + 24, i, hit = 0;              // just under the sticky bar
    for (i = 0; i < targets.length; i++) {
      if (targets[i] && targets[i].getBoundingClientRect().top <= line) hit = i;
    }
    setActive(hit);
  }
  function onScroll() { if (!ticking) { ticking = true; (window.requestAnimationFrame || setTimeout)(update); } }

  function close() { if (menu && menu.open) menu.open = false; }
  window.addEventListener("scroll", onScroll, { passive: true });
  window.addEventListener("resize", onScroll);
  links.forEach(function (a, i) { a.addEventListener("click", function () { setActive(i); close(); }); });
  Array.prototype.forEach.call(nav.querySelectorAll(".nav-side-list a"), function (a) {
    a.addEventListener("click", function () { setActive(links.map(function (l) { return l.getAttribute("href"); }).indexOf(a.getAttribute("href"))); });
  });
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape" && menu && menu.open) { menu.open = false; menu.querySelector("summary").focus(); }
  });
  document.addEventListener("click", function (e) { if (menu && menu.open && !nav.contains(e.target)) close(); });
  update();
})();
