pisg landing page
=================

index.html is a single static file: the statistics of your statistics. A headline for all channels
together, a few facts (lines a day, busiest hour, links, questions), a row per channel to compare
them (volume, busiest hour, a 24-hour profile, the last 30 days) and the top talkers of each. Every
channel name links to that channel's own page. No PHP, no cron job, no cache to refresh.

How it works
  pisg writes channels.json next to each channel page every time it runs (option
  ChannelIndex, on by default): totals, an hour-by-hour profile, the last 30 days and the top
  talkers of that channel. index.html only reads that file, so it always matches the pages.

To use it
  1. Copy index.html into the folder your channel pages are written to (the folder
     that holds channels.json).
  2. Open that folder in a browser. Web servers pick index.html before index.php.
  3. Optional: edit SITE_TITLE and SITE_LEAD near the top of index.html.

Works on any static host, including GitHub Pages. Old links such as  https://example.org/stats/#canada
still work: they jump straight to that channel's page.
