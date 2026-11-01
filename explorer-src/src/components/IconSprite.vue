<!-- explorer UI v5.0 — icon sprite: the official miuix-vue icon set (HyperOS extended icons,
     regular weight — the MiuixIcon default), imported from 'miuix-vue/icons' (Task 57).
     D10 icon clause amended by owner order #2 "full use miuix": Material → miuix.
     Task 59 fix #1: miuix glyph data is authored FONT-STYLE (y-up) — the official MiuixIcon
     renders every path with transform matrix(1 0 0 -1 0 vh) (vh is "the flip transform's ty"
     per ExtendedIconWeightData). The sprite now applies the SAME flip — without it every
     glyph rendered y-mirrored (owner bug report: "all icons upside down").
     Task 59 fix #3: i-logo is no longer a hand-drawn vector — it renders the miuix FolderFill
     glyph through the same pipeline (owner order: no generated vector images left). -->
<template>
<svg style="display:none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
  <symbol v-for="(g, id) in glyphs" :key="id" :id="'i-' + id" :viewBox="'0 0 ' + g.vw + ' ' + g.vh"><path :d="g.d" :transform="FLIP(g)" fill="currentColor" fill-rule="nonzero" clip-rule="nonzero"/></symbol>
</svg>
</template>

<script setup>
// HyperOS extended icons, regular weight (W) — glyph data verbatim from miuix-vue.
// The path data is authored font-style (y-up): every symbol applies the official
// MiuixIcon flip transform matrix(1 0 0 -1 0 vh) — see template (Task 59 fix #1).
// i-logo = FolderFill (Task 59 fix #3 — the hand-drawn brand vector is gone).
// Mapping notes (Task 57 audit): sun/moon → miuix Theme glyph (the set ships no sun/moon;
// the toggle state stays visible via the live theme switch + snackbar);
// doc→Notes · pdf/file→File · data→Layers (rows of data) · code→Edit · pkg→Store (package bag)
// office→ScreenMirroring (slide/screen) · clock→Recent · warn→Report (shield-i) · spark→TopDownloads
// (trophy, Release Health) · release→Send (paper plane) · restart→Refresh · restore→Reset · open→Link.
import { Search, Close, Ok, GridView, ListView, Theme, ExpandLess, ExpandMore,
  ChevronForward, Download, Show, Notes, File, Folder, FolderFill, Image, Layers, Edit, Store,
  ScreenMirroring, Recent, Tasks, Report, Info, TopDownloads, Copy, Send,
  Refresh, Reset, Backup, Link } from 'miuix-vue/icons'

const W = i => i.regular

// Task 59 fix #1: miuix path data is authored font-style (y-up) — the official
// MiuixIcon renders every path flipped: transform matrix(1 0 0 -1 0 vh), where
// vh is "the flip transform's ty" (ExtendedIconWeightData). Kept in script (not
// an inline template string): the SFC tokenizer chokes on a paren-heavy string
// literal sharing an element with the multi-quote :viewBox binding.
const FLIP = g => 'matrix(1 0 0 -1 0 ' + g.vh

const glyphs = {
  logo: W(FolderFill),
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
