<!-- explorer UI v5.0 — icon sprite: the official miuix-vue icon set (HyperOS extended icons,
     regular weight — the MiuixIcon default), imported from 'miuix-vue/icons' (Task 57).
     D10 icon clause amended by owner order #2 "full use miuix": Material → miuix.
     The <use href="#i-…"> contract is unchanged — every consumer keeps working; only the
     glyph data source changed. i-logo stays the app brand mark (no miuix equivalent). -->
<template>
<svg style="display:none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
  <symbol id="i-logo" viewBox="0 0 24 24"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 1 0-20zm3.5 13.5-7 3 3-7 7-3-3 7z"/></symbol>
  <symbol v-for="(g, id) in glyphs" :key="id" :id="'i-' + id" :viewBox="'0 0 ' + g.vw + ' ' + g.vh"><path :d="g.d"/></symbol>
</svg>
</template>

<script setup>
// HyperOS extended icons, regular weight (W) — glyph data verbatim from miuix-vue.
// Mapping notes (Task 57 audit): sun/moon → miuix Theme glyph (the set ships no sun/moon;
// the toggle state stays visible via the live theme switch + snackbar);
// doc→Notes · pdf/file→File · data→Layers (rows of data) · code→Edit · pkg→Store (package bag)
// office→ScreenMirroring (slide/screen) · clock→Recent · warn→Report (shield-i) · spark→TopDownloads
// (trophy, Release Health) · release→Send (paper plane) · restart→Refresh · restore→Reset · open→Link.
import { Search, Close, Ok, GridView, ListView, Theme, ExpandLess, ExpandMore,
  ChevronForward, Download, Show, Notes, File, Folder, Image, Layers, Edit, Store,
  ScreenMirroring, Recent, Tasks, Report, Info, TopDownloads, Copy, Send,
  Refresh, Reset, Backup, Link } from 'miuix-vue/icons'

const W = i => i.regular

const glyphs = {
  search: W(Search),
  folder: W(Folder),
  close: W(Close),
  check: W(Ok),
  grid: W(GridView),
  list: W(ListView),
  sun: W(Theme),
  moon: W(Theme),
  up: W(ExpandLess),
  chev: W(ExpandMore),
  chevr: W(ChevronForward),
  down: W(Download),
  eye: W(Show),
  doc: W(Notes),
  pdf: W(File),
  img: W(Image),
  data: W(Layers),
  code: W(Edit),
  pkg: W(Store),
  office: W(ScreenMirroring),
  file: W(File),
  clock: W(Recent),
  task: W(Tasks),
  warn: W(Report),
  info: W(Info),
  spark: W(TopDownloads),
  copy: W(Copy),
  release: W(Send),
  restart: W(Refresh),
  restore: W(Reset),
  backup: W(Backup),
  open: W(Link)
}
</script>
