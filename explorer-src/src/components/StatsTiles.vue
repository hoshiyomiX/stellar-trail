<script setup>
// explorer UI v5.0 — Dashboard tiles (Task 63 owner order #1: the section is
// renamed "Release Health" → "Dashboard"; same 4 tiles, D10 lock untouched).
// A verbatim port of the v4.4 renderStats (D10 lock: the 4 tiles with official
// icons, compact typography).
// Task 61 retired this component with the whole body chrome; Task 62 (owner order
// "Revert back dashboard card tiles that you had removed", clarifying that "below"
// meant the TOP BAR contents) restores it verbatim from the pre-Task-61 form.
import { computed } from 'vue'
import { META } from '../explorer.js'

const cells = computed(() => {
  const m = META.value
  if (!m) return []
  const g = m.guard || {}, rs = m.resets || {}
  const syncTxt = !g || !g.installed ? 'skill not installed'
    : g.in_sync ? 'in sync with canonical'
    : g.canonical_present === false ? 'no canonical yet — run bootstrap --ensure'
    : 'drift vs canonical ' + (g.canonical_version || '?')
  const wTxt = g && g.watcher_alive ? 'watcher alive' : 'watcher down'
  const cell = (o, label, cls, icon) => {
    const c = (o && o.count != null) ? o.count : 0
    const last = (o && o.last) ? o.last : 'never'
    return { k: label, v: String(c), s: 'last: ' + last, icon, cls }
  }
  return [
    { k: 'Skill Version', v: 'v' + ((g && g.live_version) || '?'),
      s: (g && g.watcher_alive ? ' watcher-alive' : '') + ' — ' + syncTxt + ' · ' + wTxt,
      icon: 'release', cls: 'primary', dot: !!(g && g.watcher_alive) },
    cell(rs.boot && rs.boot.boots, 'Boot Resets', 'doc', 'restart'),
    cell(rs.boot && rs.boot.skill_restores, 'Skill Restores', 'data', 'restore'),
    cell(rs.boot && rs.boot.archive_applies, 'Snapshot Restores', 'img', 'backup'),
  ]
})
</script>
<template>
  <section aria-label="Dashboard">
    <!-- Task 63 order #1: title "Release Health" → "Dashboard"; the trophy glyph
         (TopDownloads) left with the old name — the section now carries the GridView
         glyph, the HyperOS dashboard-grid metaphor. -->
    <div class="smalltitle"><svg class="ic"><use href="#i-grid"/></svg>Dashboard</div>
    <div class="statgrid" id="stats">
      <div v-for="(t, i) in cells" :key="i" class="statcard">
        <div class="top">
          <span class="tile40" :class="'tile40--' + t.cls"><svg class="ic"><use :href="'#i-' + t.icon"/></svg></span>
          <span class="k">{{ t.k }}</span>
        </div>
        <div class="v">{{ t.v }}</div>
        <div class="s">
          <template v-if="i === 0"><span class="gdot" :class="t.dot ? 'on' : 'off'"></span>{{ t.s }}</template>
          <template v-else>{{ t.s }}</template>
        </div>
      </div>
    </div>
  </section>
</template>
