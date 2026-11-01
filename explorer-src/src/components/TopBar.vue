<script setup>
// explorer UI v5.0 — TopAppBar: the v4.4 hand-rolled header is replaced by the
// REAL miuix-vue TopAppBar (Task 53 component-layer swap); the chips row, the
// Rescan and the theme toggle keep their v4.4 behavior verbatim.
import { computed } from 'vue'
import { MiuixTopAppBar, MiuixIconButton } from 'miuix-vue'
import { ui, META, onScan } from '../explorer.js'
import { toggleTheme } from '../theme.js'

const verTxt = computed(() => META.value ? ('v' + ((META.value.guard && META.value.guard.live_version) || '?')) : '…')
</script>
<template>
  <MiuixTopAppBar title="Task Files Explorer" subtitle="Miuix · download/ + archive/ dashboard">
    <template #navigation>
      <span class="appbar-logo" aria-hidden="true"><svg class="ic"><use href="#i-logo"/></svg></span>
    </template>
    <template #actions>
      <span class="chip chip--primary" id="verChip" title="UI build — shows the stellar-trail version once explorer.py answers">
        <svg class="ic"><use href="#i-release"/></svg><span id="verTxt">UI 5.0 · {{ verTxt }}</span>
      </span>
      <span class="chip" id="clock" title="local time"><svg class="ic"><use href="#i-clock"/></svg>{{ ui.clock }}</span>
      <MiuixIconButton id="scanBtn" title="Rescan now — refresh the file inventory from the server" aria-label="Rescan now" @click="onScan">
        <svg class="ic" id="scanIcon" :class="{ spinning: ui.spinning }"><use href="#i-restart"/></svg>
      </MiuixIconButton>
      <MiuixIconButton id="themeBtn" title="Toggle dark / light theme" aria-label="Toggle theme" @click="toggleTheme">
        <svg class="ic" id="themeIcon"><use :href="ui.themeDark ? '#i-moon' : '#i-sun'"/></svg>
      </MiuixIconButton>
    </template>
  </MiuixTopAppBar>
</template>
