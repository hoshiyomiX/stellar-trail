<script setup>
// explorer UI v5.0 — Task History rail, a verbatim port of the v4.4 renderTasks.
// The rail data (TASKS) is replaced by the engine ONLY on real content change
// (content-signature rule) — in-place patching preserves scrollLeft automatically.
import { computed } from 'vue'
import { S, TASKS, META } from '../explorer.js'

const ts = computed(() => TASKS.value ? [...TASKS.value].slice(-14).reverse() : [])
const activeTask = computed(() => {
  if (!S.task) return null
  const t = (META.value && META.value.tasks || []).find(x => x.id === S.task)
  return { id: t ? t.id : S.task, title: t ? t.title : '' }
})
function go(id){ S.task = S.task === id ? null : id; S.page = 1 }
function onKey(e, id){ if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); go(id) } }
function clearTask(){ S.task = null; S.page = 1 }
</script>
<template>
  <section aria-labelledby="secTask">
    <div class="smalltitle"><svg class="ic"><use href="#i-task"/></svg><span id="secTask">Task History</span>
      <span class="note">parsed from worklog.md — full titles, scroll sideways; click a card to filter its related files</span></div>
    <div class="taskrail" id="taskRail" role="list" tabindex="0" aria-label="Task history — scroll horizontally with arrow keys">
      <div v-if="!ts.length" class="rail-empty">worklog.md has no Task section yet — this rail fills in automatically once one exists.</div>
      <template v-else>
        <div v-for="t in ts" :key="t.id" class="tcard" :class="{ active: S.task === t.id }" role="listitem" tabindex="0"
             :data-id="t.id" @click="go(t.id)" @keydown="e => onKey(e, t.id)">
          <div class="th"><svg class="ic tick"><use href="#i-check"/></svg><span class="tid">TASK {{ t.id }}</span></div>
          <div class="tt">{{ t.title }}</div>
          <div class="tc"><span>{{ t.count }} related files</span><svg class="ic"><use href="#i-chevr"/></svg></div>
        </div>
      </template>
    </div>
    <div id="activeFilter" v-if="activeTask">
      <span class="ichip"><span>Active filter — TASK {{ activeTask.id }}: {{ activeTask.title }}</span>
        <button class="x" @click="clearTask" title="Remove filter" aria-label="Remove the task filter">
          <svg class="ic"><use href="#i-close"/></svg></button></span>
    </div>
  </section>
</template>
