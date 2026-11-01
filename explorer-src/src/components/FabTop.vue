<script setup>
// explorer UI v5.0 — back-to-top: the v4.4 hand-rolled .fab button is replaced
// by the REAL miuix-vue FloatingActionButton (Task 53); the >600px show rule
// and the smooth scroll are ported verbatim.
import { onMounted, onBeforeUnmount } from 'vue'
import { MiuixFloatingActionButton } from 'miuix-vue'
import { ui } from '../explorer.js'

function onScroll(){ ui.fab = window.scrollY > 600 }
function toTop(){ window.scrollTo({ top: 0, behavior: 'smooth' }) }
onMounted(() => window.addEventListener('scroll', onScroll, { passive: true }))
onBeforeUnmount(() => window.removeEventListener('scroll', onScroll))
</script>
<template>
  <MiuixFloatingActionButton v-if="ui.fab" title="Back to top" aria-label="Back to top" @click="toTop">
    <svg class="ic"><use href="#i-up"/></svg>
  </MiuixFloatingActionButton>
</template>
