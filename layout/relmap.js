/* Relation map: who talks to whom.
 *
 * pisg writes the data as JSON in <script id="relmap-data"> and this script draws it as
 * an SVG into <svg id="relmap-svg">, with details in <div id="relmap-info">.
 * No libraries. The layout is a small force simulation with a fixed starting point, so
 * the same data always gives the same picture.
 *
 * data = { nodes: [{id, lines, words, hours:[4], partners:[[nick, strength]...]}],
 *          edges: [{a, b, w, ab:[direct, mentions, replies], ba:[...]}],   // a, b = node index
 *          i18n:  { text key: text } }
 */
(function () {
  "use strict";

  var dataEl = document.getElementById("relmap-data");
  var svg = document.getElementById("relmap-svg");
  var info = document.getElementById("relmap-info");
  if (!dataEl || !svg || !info) return;

  var data;
  try { data = JSON.parse(dataEl.textContent); } catch (e) { return; }
  var nodes = data.nodes || [], edges = data.edges || [], T = data.i18n || {};
  if (nodes.length < 2 || !edges.length) return;

  var NS = "http://www.w3.org/2000/svg";
  var W = 960, H = 620, PAD = 40;

  function fmt(s, vars) {
    return String(s || "").replace(/\[:(\w+)\]/g, function (m, k) { return vars && vars[k] !== undefined ? vars[k] : m; });
  }
  function num(n) { return Number(n || 0).toLocaleString(); }
  function el(name, attrs, text) {
    var e = document.createElementNS(NS, name);
    for (var k in attrs) if (Object.prototype.hasOwnProperty.call(attrs, k)) e.setAttribute(k, attrs[k]);
    if (text !== undefined) e.textContent = text;
    return e;
  }
  function html(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  // ---- sizes and colours -------------------------------------------------------------
  var maxLines = 1, maxW = 1;
  nodes.forEach(function (n) { if (n.lines > maxLines) maxLines = n.lines; });
  edges.forEach(function (e) { if (e.w > maxW) maxW = e.w; });
  nodes.forEach(function (n) {
    n.r = 7 + 20 * Math.sqrt(n.lines / maxLines);
    var best = 0;
    for (var i = 1; i < 4; i++) if ((n.hours[i] || 0) > (n.hours[best] || 0)) best = i;
    n.t = best;                                   // 0 night, 1 morning, 2 afternoon, 3 evening
  });

  // ---- layout (Fruchterman-Reingold, fixed start, so it is repeatable) -----------------
  function layout() {
    var n = nodes.length, i, j, k;
    var pos = nodes.map(function (nd, idx) {
      var a = (2 * Math.PI * idx) / n;
      return { x: W / 2 + 0.36 * W * Math.cos(a), y: H / 2 + 0.36 * H * Math.sin(a), dx: 0, dy: 0 };
    });
    var area = (W - 2 * PAD) * (H - 2 * PAD);
    var kk = 0.75 * Math.sqrt(area / n);
    var steps = 320;
    for (var s = 0; s < steps; s++) {
      var temp = (W / 9) * (1 - s / steps) + 0.5;
      for (i = 0; i < n; i++) { pos[i].dx = 0; pos[i].dy = 0; }
      for (i = 0; i < n; i++) {                   // everyone pushes everyone away
        for (j = i + 1; j < n; j++) {
          var dx = pos[i].x - pos[j].x, dy = pos[i].y - pos[j].y;
          var d = Math.sqrt(dx * dx + dy * dy) || 0.01;
          var minGap = nodes[i].r + nodes[j].r + 14;
          var f = (kk * kk) / d + (d < minGap ? (minGap - d) * 2 : 0);
          pos[i].dx += (dx / d) * f; pos[i].dy += (dy / d) * f;
          pos[j].dx -= (dx / d) * f; pos[j].dy -= (dy / d) * f;
        }
      }
      for (k = 0; k < edges.length; k++) {        // linked people pull together, harder when they talk more
        var e = edges[k], a = pos[e.a], b = pos[e.b];
        var ex = a.x - b.x, ey = a.y - b.y;
        var ed = Math.sqrt(ex * ex + ey * ey) || 0.01;
        var pull = ((ed * ed) / kk) * (0.15 + 0.85 * Math.sqrt(e.w / maxW));
        a.dx -= (ex / ed) * pull; a.dy -= (ey / ed) * pull;
        b.dx += (ex / ed) * pull; b.dy += (ey / ed) * pull;
      }
      for (i = 0; i < n; i++) {                   // a little gravity keeps loners on the page
        pos[i].dx -= (pos[i].x - W / 2) * 0.05; pos[i].dy -= (pos[i].y - H / 2) * 0.05;
        var len = Math.sqrt(pos[i].dx * pos[i].dx + pos[i].dy * pos[i].dy) || 0.01;
        var move = Math.min(len, temp);
        pos[i].x += (pos[i].dx / len) * move; pos[i].y += (pos[i].dy / len) * move;
      }
    }
    // Not to scale, on purpose. Fitting the drawing to its farthest nodes squeezes the busy middle
    // into a blob, so keep only each node's direction from the centre and re-space them by rank:
    // the nearest goes near the middle, the farthest to the edge, evenly in between.
    var cx = median(pos.map(function (q) { return q.x; })), cy = median(pos.map(function (q) { return q.y; }));
    var sx = Math.max(median(pos.map(function (q) { return Math.abs(q.x - cx); })), 1);
    var sy = Math.max(median(pos.map(function (q) { return Math.abs(q.y - cy); })), 1);
    var polar = pos.map(function (q, idx) {
      var nx = (q.x - cx) / sx, ny = (q.y - cy) / sy;
      return { i: idx, a: Math.atan2(ny, nx), d: Math.sqrt(nx * nx + ny * ny) };
    });
    polar.sort(function (p, q) { return p.d - q.d || p.i - q.i; });
    var RX = W / 2 - PAD - 34, RY = H / 2 - PAD - 26;
    polar.forEach(function (p, rank) {
      var t = Math.pow((rank + 0.6) / (n + 0.2), 0.62);           // <1 keeps more room near the middle
      nodes[p.i].x = W / 2 + Math.cos(p.a) * RX * t;
      nodes[p.i].y = H / 2 + Math.sin(p.a) * RY * t;
    });
    // stretch the result to fill the picture, so no band of it stays empty
    var x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    nodes.forEach(function (nd) { x0 = Math.min(x0, nd.x); x1 = Math.max(x1, nd.x); y0 = Math.min(y0, nd.y); y1 = Math.max(y1, nd.y); });
    nodes.forEach(function (nd) {
      nd.x = (PAD + 30) + ((nd.x - x0) / ((x1 - x0) || 1)) * (W - 2 * (PAD + 30));
      nd.y = (PAD + 8) + ((nd.y - y0) / ((y1 - y0) || 1)) * (H - 2 * PAD - 44);
    });
    separate();
  }

  function median(a) { return pct(a, 0.5); }
  function pct(a, p) {
    var b = a.slice().sort(function (x, y) { return x - y; });
    return b[Math.min(b.length - 1, Math.floor(p * b.length))];
  }
  // Push apart circles that still overlap, keeping every node (and room for its label) in the picture.
  function separate() {
    var n = nodes.length;
    for (var pass = 0; pass < 200; pass++) {
      var moved = false;
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          var dx = nodes[i].x - nodes[j].x, dy = nodes[i].y - nodes[j].y;
          var d = Math.sqrt(dx * dx + dy * dy);
          var gap = nodes[i].r + nodes[j].r + 10;
          if (d < gap) {
            if (d < 0.01) { dx = 1; dy = 0; d = 1; }
            var push = (gap - d) / 2 + 0.05;
            nodes[i].x += (dx / d) * push; nodes[i].y += (dy / d) * push;
            nodes[j].x -= (dx / d) * push; nodes[j].y -= (dy / d) * push;
            moved = true;
          }
        }
      }
      for (i = 0; i < n; i++) {
        nodes[i].x = Math.max(nodes[i].r + 8, Math.min(W - nodes[i].r - 8, nodes[i].x));
        nodes[i].y = Math.max(nodes[i].r + 8, Math.min(H - nodes[i].r - 22, nodes[i].y));
      }
      if (!moved) break;
    }
  }
  layout();

  // Labels: busiest nodes first, each tried below, above, right, then left of its circle, and kept
  // only where it touches no other label and no circle. The rest show on hover or when selected.
  function placeLabels() {
    var boxes = [], order = nodes.map(function (_, i) { return i; })
      .sort(function (a, b) { return nodes[b].lines - nodes[a].lines; });
    function hits(b) {
      for (var k = 0; k < boxes.length; k++) {
        var o = boxes[k];
        if (b.x < o.x + o.w && b.x + b.w > o.x && b.y < o.y + o.h && b.y + b.h > o.y) return true;
      }
      for (k = 0; k < nodes.length; k++) {
        var c = nodes[k];
        if (c.x + c.r + 3 > b.x && c.x - c.r - 3 < b.x + b.w && c.y + c.r + 3 > b.y && c.y - c.r - 3 < b.y + b.h) return true;
      }
      return false;
    }
    order.forEach(function (i) {
      var n = nodes[i], w = shorten(n.id).length * 6.7 + 4, h = 14;
      var tries = [
        { a: "middle", x: n.x, y: n.y + n.r + 12, bx: n.x - w / 2, by: n.y + n.r + 1 },
        { a: "middle", x: n.x, y: n.y - n.r - 4, bx: n.x - w / 2, by: n.y - n.r - 15 },
        { a: "start", x: n.x + n.r + 4, y: n.y + 4, bx: n.x + n.r + 3, by: n.y - 7 },
        { a: "end", x: n.x - n.r - 4, y: n.y + 4, bx: n.x - n.r - w - 3, by: n.y - 7 }
      ];
      n.label = null;
      for (var t = 0; t < tries.length; t++) {
        var b = { x: tries[t].bx, y: tries[t].by, w: w, h: h };
        if (b.x < 2 || b.x + b.w > W - 2 || b.y < 2 || b.y + b.h > H - 2) continue;
        if (!hits(b)) { n.label = tries[t]; boxes.push(b); break; }
      }
      if (!n.label) n.label = { a: "middle", x: n.x, y: n.y + n.r + 12, hidden: true };
    });
  }
  function shorten(s) { return s.length > 15 ? s.slice(0, 14) + "\u2026" : s; }
  placeLabels();

  // ---- drawing --------------------------------------------------------------------------
  var edgeLayer = el("g", { "class": "rm-edges" }), nodeLayer = el("g", { "class": "rm-nodes" });
  svg.appendChild(edgeLayer);
  svg.appendChild(nodeLayer);

  var nodeEls = [], edgeEls = [], neighbours = nodes.map(function () { return {}; });

  edges.forEach(function (e, idx) {
    var a = nodes[e.a], b = nodes[e.b];
    neighbours[e.a][e.b] = idx; neighbours[e.b][e.a] = idx;
    var width = 1 + 6 * Math.sqrt(e.w / maxW);
    var g = el("g", { "class": "rm-edge" });
    g.appendChild(el("line", { "class": "rm-hit", x1: a.x, y1: a.y, x2: b.x, y2: b.y, "stroke-width": Math.max(14, width + 8) }));
    g.appendChild(el("line", { "class": "rm-line", x1: a.x, y1: a.y, x2: b.x, y2: b.y, "stroke-width": width.toFixed(2) }));
    g.appendChild(el("title", {}, fmt(T.rel_between, { a: a.id, b: b.id }) + " - " + T.rel_strength + " " + num(e.w)));
    g.addEventListener("click", function (ev) { ev.stopPropagation(); selectEdge(idx); });
    edgeLayer.appendChild(g);
    edgeEls.push(g);
  });


  nodes.forEach(function (n, idx) {
    var g = el("g", { "class": "rm-node t" + n.t, tabindex: "0", role: "button",
                      "aria-label": n.id + ", " + num(n.lines) + " " + T.rel_lines });
    g.appendChild(el("circle", { cx: n.x, cy: n.y, r: n.r.toFixed(1) }));
    g.appendChild(el("text", { x: n.label.x.toFixed(1), y: n.label.y.toFixed(1), "text-anchor": n.label.a,
                               "class": n.label.hidden ? "rm-lbl off" : "rm-lbl" }, shorten(n.id)));
    g.appendChild(el("title", {}, n.id + " - " + num(n.lines) + " " + T.rel_lines));
    g.addEventListener("click", function (ev) { ev.stopPropagation(); selectNode(idx); });
    g.addEventListener("keydown", function (ev) {
      if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); selectNode(idx); }
    });
    g.addEventListener("mouseenter", function () { focusNode(idx); });
    g.addEventListener("mouseleave", function () { if (selected === null) clearFocus(); else focusSelection(); });
    nodeLayer.appendChild(g);
    nodeEls.push(g);
  });

  // ---- highlighting ------------------------------------------------------------------------
  var selected = null;                             // {type: "node"|"edge", i}

  function setClasses(nodeSet, edgeSet, selNode, selEdge) {
    var dim = !!(nodeSet || edgeSet);
    svg.classList.toggle("dim", dim);
    nodeEls.forEach(function (g, i) {
      g.classList.toggle("hl", !!(nodeSet && nodeSet[i]));
      g.classList.toggle("sel", selNode === i);
    });
    edgeEls.forEach(function (g, i) {
      g.classList.toggle("hl", !!(edgeSet && edgeSet[i]));
      g.classList.toggle("sel", selEdge === i);
    });
  }
  function focusNode(i) {
    var ns = {}, es = {};
    ns[i] = true;
    for (var j in neighbours[i]) { ns[j] = true; es[neighbours[i][j]] = true; }
    setClasses(ns, es, selected && selected.type === "node" ? selected.i : null, null);
  }
  function clearFocus() { setClasses(null, null, null, null); }
  function focusSelection() {
    if (!selected) return clearFocus();
    if (selected.type === "node") focusNode(selected.i);
    else {
      var e = edges[selected.i], ns = {}, es = {};
      ns[e.a] = true; ns[e.b] = true; es[selected.i] = true;
      setClasses(ns, es, null, selected.i);
    }
  }

  // ---- details panel --------------------------------------------------------------------------
  var BUCKETS = ["rel_time0", "rel_time1", "rel_time2", "rel_time3"];

  function reset() {
    selected = null;
    clearFocus();
    info.textContent = T.rel_pick || "";
  }

  function line(label, parts) { var p = html("p", "ri-row"); p.appendChild(html("b", "", label + " ")); p.appendChild(document.createTextNode(parts)); return p; }

  function selectNode(i) {
    selected = { type: "node", i: i };
    focusSelection();
    var n = nodes[i];
    info.textContent = "";
    info.appendChild(html("h4", "ri-title", n.id));
    info.appendChild(html("p", "ri-meta", num(n.lines) + " " + T.rel_lines + " · " + num(n.words) + " " + T.rel_words));
    info.appendChild(html("p", "ri-meta", T.rel_active + " " + (T[BUCKETS[n.t]] || "")));
    if (n.partners && n.partners.length) {
      info.appendChild(html("h5", "ri-sub", T.rel_partners));
      var ul = html("ul", "ri-list");
      n.partners.forEach(function (p) {
        var li = html("li", ""), idx = -1;
        nodes.forEach(function (o, k) { if (o.id === p[0]) idx = k; });
        if (idx >= 0) {
          var b = html("button", "ri-link", p[0]);
          b.type = "button";
          b.addEventListener("click", function () { selectNode(idx); });
          li.appendChild(b);
        } else li.appendChild(document.createTextNode(p[0]));
        li.appendChild(html("span", "ri-num", num(p[1])));
        ul.appendChild(li);
      });
      info.appendChild(ul);
    }
  }

  function selectEdge(i) {
    selected = { type: "edge", i: i };
    focusSelection();
    var e = edges[i], a = nodes[e.a].id, b = nodes[e.b].id;
    info.textContent = "";
    info.appendChild(html("h4", "ri-title", fmt(T.rel_between, { a: a, b: b })));
    info.appendChild(html("p", "ri-meta", T.rel_strength + ": " + num(e.w)));
    function dir(from, to, v) {
      return line(fmt(T.rel_toward, { a: from, b: to }) + ":",
                  num(v[0]) + " " + T.rel_direct + ", " + num(v[1]) + " " + T.rel_mentions);
    }
    info.appendChild(dir(a, b, e.ab));
    info.appendChild(dir(b, a, e.ba));
    info.appendChild(line(T.rel_replies + ":", num(e.ab[2] + e.ba[2])));
  }

  svg.addEventListener("click", reset);
  document.addEventListener("keydown", function (ev) { if (ev.key === "Escape" && selected) reset(); });
  info.textContent = T.rel_pick || "";
})();
