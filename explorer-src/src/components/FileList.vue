<script setup>
// explorer UI v5.0 — file list, a verbatim port of the v4.4 renderList/renderError/
// renderStatic/cardHTML/pager + the v4.1 silent-refresh animation rule.
import { computed } from 'vue'
import { S, PAGE, META, ui, PAGE_MAP, loadList, resetErrorAndRetry, goLive, copyPath, fetchT } from '../explorer.js'
import { fmtSize, fmtDate, fmtRel, iconFor, classFor } from '../util.js'
import { md, hlJSON } from '../preview.js'

const emit = defineEmits(['preview'])

// Task 61 (owner order "hapus semua button & label"): the listhead rootline
// (All locations · download/ + archive/ · showing 1–N of N) is RETIRED with the
// rest of the body labels — the cards speak for themselves; locName/rootPaths/
// from_/to_/shown died with it.
function crumb(f){
  const i = f.rel.lastIndexOf('/')
  return i < 0 ? { dir: '', name: f.rel } : { dir: f.rel.slice(0, i + 1), name: f.rel.slice(i + 1) }
}
function delay(i){ return Math.min(i * 16, 280) + 'ms' }
function page(n){ S.page = n; loadList() }
function onCardKey(e, f){
  if (e.key !== 'Enter' && e.key !== ' ') return
  if (e.target.closest('button,a,input,select')) return
  e.preventDefault(); emit('preview', f)
}
</script>
<template>
  <section id="listwrap" aria-label="Files">
    <div id="listbody">
      <!-- static-copy graceful mode — informational banner, never an error; Task 67: AUTO-breakout to the live root the moment the live feed answers on this origin (the manual button stays as the blocked-navigation fallback) -->
      <div v-if="ui.static" class="empty">
        <div class="e" style="background:var(--mx-tertiary-container);color:var(--mx-on-tertiary-container)"><svg class="ic"><use href="#i-info"/></svg></div>
        <div class="t">{{ ui.staticLive ? 'Static copy — live explorer reachable' : 'Static copy — live data unavailable' }}</div>
        <template v-if="ui.staticLive">
          <div class="h">explorer.py answered from this origin — recovering the live view… (Task 67 auto-breakout: the platform file-preview chrome is replaced by the live app; if this frame is still here, top-level navigation was blocked — use the button)</div>
          <button class="btn" @click="goLive()"><svg class="ic"><use href="#i-open"/></svg>Open live view</button>
        </template>
        <template v-else>
          <div class="h">this page was opened as a plain file, without explorer.py — the /api feeds behind the tiles, task rail, and search do not exist on this origin</div>
          <div class="h">the live Task Files Explorer is served at the preview URL root while a session is running</div>
        </template>
      </div>
      <!-- honest error state (v4.3.1 watchdog / steady retry) -->
      <div v-else-if="ui.error" class="empty">
        <div class="e" style="background:var(--mx-error-container);color:var(--mx-on-error-container)"><svg class="ic"><use href="#i-warn"/></svg></div>
        <div class="t">Failed to load data from explorer.py</div>
        <div class="h">server not responding — the connection may be temporarily down · UI v5.0</div>
        <button class="btn" @click="resetErrorAndRetry()"><svg class="ic"><use href="#i-down"/></svg>Retry</button>
      </div>
      <!-- first paint -->
      <div v-else-if="!PAGE" class="loadcard"><div class="spinner"></div><p>loading file inventory…</p></div>
      <!-- empty result -->
      <div v-else-if="!PAGE.total" class="empty">
        <div class="e t-other"><svg class="ic"><use href="#i-search"/></svg></div>
        <div class="t">No files match the active filters</div>
        <div class="h">no files in download/ + archive/ yet — the list fills in as work produces deliverables</div>
      </div>
      <!-- the grid / list -->
      <div v-else class="filegrid" :class="{ 'filegrid--list': S.view === 'list', noanim: !ui.listAnim }">
        <div v-for="(f, i) in PAGE.files" :key="f.key" class="fcard" tabindex="0" role="button"
             :aria-label="'Preview ' + f.name" :style="{ animationDelay: ui.listAnim ? delay(i) : '0ms' }"
             @click="emit('preview', f)" @keydown="e => onCardKey(e, f)">
          <span class="ftile" :class="'t-' + classFor(f)"><svg class="ic"><use :href="'#i-' + iconFor(f)"/></svg></span>
          <div class="fbody">
            <!-- Task 66: fbadge moved INSIDE .fbody as a right float — the
                 card-level absolute corner badge collided with .fnm line 1
                 on long filenames (12+/41 cards, VLM-caught, DOM-measured).
                 Same corner slot; name wraps short of it, lines 2+ full width. -->
            <span class="fbadge">{{ f.ext || f.type }}</span>
            <div class="fnm"><span class="cd">{{ crumb(f).dir }}</span><span>{{ crumb(f).name }}</span></div>
            <div class="fmeta"><span>{{ fmtSize(f.size) }}</span><span :title="fmtDate(f.mtime)">{{ fmtRel(f.mtime) }}</span></div>
            <span v-if="f.task" class="ftask"><svg class="ic"><use href="#i-check"/></svg>TASK {{ f.task }}</span>
            <div class="fact">
              <button class="fcpy" :title="'Copy the server path'" :aria-label="'Copy the path of ' + f.name" @click.stop="copyPath(f)"><svg class="ic"><use href="#i-copy"/></svg></button>
              <a :href="f.href + '?dl=1'" :download="f.name" :title="'Download ' + f.name" :aria-label="'Download ' + f.name" @click.stop><svg class="ic"><use href="#i-down"/></svg></a>
            </div>
          </div>
        </div>
      </div>
    </div>
    <div class="pager" id="pager" v-if="PAGE && PAGE.pages > 1 && !ui.error && !ui.static">
      <button title="First page" :disabled="PAGE.page <= 1" @click="page(1)"><svg class="ic"><use href="#i-chevr"/></svg><span style="transform:scaleX(-1);display:inline-flex"><svg class="ic"><use href="#i-chevr"/></svg></span></button>
      <button title="Previous page" :disabled="PAGE.page <= 1" @click="page(Math.max(1, PAGE.page - 1))"><svg class="ic"><use href="#i-chev"/></svg></button>
      <span class="pinfo">{{ PAGE.page }} / {{ PAGE.pages }}</span>
      <button title="Next page" :disabled="PAGE.page >= PAGE.pages" @click="page(Math.min(PAGE.pages, PAGE.page + 1))"><svg class="ic"><use href="#i-chev"/></svg></button>
      <button title="Last page" :disabled="PAGE.page >= PAGE.pages" @click="page(PAGE.pages)"><span style="transform:scaleX(-1);display:inline-flex"><svg class="ic"><use href="#i-chevr"/></svg></span><svg class="ic"><use href="#i-chevr"/></svg></button>
    </div>
  </section>
</template>
