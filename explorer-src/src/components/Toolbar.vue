<script setup>
// explorer UI v5.0 — filter/search toolbar, a verbatim port of the v4.4 controls
// (D10 lock: compact 40px search bar — kept custom, NOT MiuixSearchBar, by the owner's
// "Bertahan penuh" answer; server-side search, 200 ms debounce).
import { ref, watch } from 'vue'
import { S, META, loadList } from '../explorer.js'
import { TYPES } from '../util.js'

const q = ref(''), qClear = ref(false), qTimer = { t: null }
const typeCounts = ref({}), total = ref(0)
const label = { all: 'All', doc: 'Documents', pdf: 'PDF', img: 'Images', data: 'Data', pkg: 'Archives', code: 'Code', office: 'Office', other: 'Other' }

watch(META, m => {
  const tc = (m && m.stats && m.stats.type_counts) || {}
  total.value = (m && m.stats && m.stats.total_files) || 0
  typeCounts.value = tc
  if (S.type !== 'all' && !tc[S.type]) S.type = 'all'   /* graceful when a type disappears */
}, { immediate: true })

function onInput(e){
  const v = e.target.value
  qClear.value = !!v
  clearTimeout(qTimer.t); qTimer.t = setTimeout(() => { S.q = v; S.page = 1; loadList() }, 200)   /* ~200 ms search debounce (server-side) */
}
function clearQ(){
  clearTimeout(qTimer.t); S.q = ''; q.value = ''; qClear.value = false; S.page = 1; loadList()
}
function pickType(t){ S.type = t; S.page = 1; loadList() }
function pickRoot(r){ S.root = r; S.page = 1; loadList() }
function pickSort(col){
  if (S.sort.col === col) S.sort.dir = S.sort.dir === 'asc' ? 'desc' : 'asc'
  else S.sort = { col, dir: col === 'mtime' ? 'desc' : 'asc' }
  S.page = 1; loadList()
}
function pickView(v){ S.view = v }
</script>
<template>
  <section aria-label="Filter and search">
    <div class="toolbar">
      <div class="searchbar" role="search">
        <svg class="ic"><use href="#i-search"/></svg>
        <input id="q" type="search" v-model="q" @input="onInput" placeholder="Search files… (name / extension / path)" aria-label="Search files">
        <button class="iconbtn" id="qClear" v-show="qClear" @click="clearQ" title="Clear search" aria-label="Clear search">
          <svg class="ic"><use href="#i-close"/></svg>
        </button>
      </div>
      <div class="toolrow">
        <button v-for="t in ['all', ...TYPES]" :key="t" class="fchip" :class="{ on: S.type === t }" :data-type="t"
                v-show="t === 'all' || (typeCounts[t] || 0) > 0" @click="pickType(t)">
          {{ label[t] }} <span class="fnum">{{ t === 'all' ? total : (typeCounts[t] || 0) }}</span>
        </button>
        <div class="seg" role="group" aria-label="Location">
          <button v-for="r in ['all', 'download', 'archive']" :key="r" :data-root="r" :class="{ on: S.root === r }" @click="pickRoot(r)">
            {{ r === 'all' ? 'All' : r === 'download' ? 'Downloads' : 'Archive' }}
          </button>
        </div>
        <div class="seg" role="group" aria-label="Sort the file list">
          <button v-for="c in ['mtime', 'name', 'size']" :key="c" class="sortbtn" :class="{ on: S.sort.col === c, asc: S.sort.col === c && S.sort.dir === 'asc' }"
                  :data-col="c" :aria-pressed="S.sort.col === c ? 'true' : 'false'" @click="pickSort(c)">
            {{ c === 'mtime' ? 'Time' : c === 'name' ? 'Name' : 'Size' }} <svg class="ic sortarr" aria-hidden="true"><use href="#i-chev"/></svg>
          </button>
        </div>
        <div class="seg" role="group" aria-label="View mode">
          <button id="vGrid" :class="{ on: S.view === 'grid' }" title="Grid view" :aria-label="'Grid view'" :aria-pressed="S.view === 'grid' ? 'true' : 'false'" @click="pickView('grid')">
            <svg class="ic"><use href="#i-grid"/></svg>Grid
          </button>
          <button id="vList" :class="{ on: S.view === 'list' }" title="List view" :aria-label="'List view'" :aria-pressed="S.view === 'list' ? 'true' : 'false'" @click="pickView('list')">
            <svg class="ic"><use href="#i-list"/></svg>List
          </button>
        </div>
      </div>
    </div>
  </section>
</template>
