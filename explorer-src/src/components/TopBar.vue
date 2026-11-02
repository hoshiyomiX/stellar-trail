<script setup>
// explorer UI v5.0 — TopAppBar. Task 62 (owner clarification: "'below" means the
// contents of the top bar (clock/version chip/Rescan/Theme)"): the appbar is
// STRIPPED to identity — the version chip, the clock, the Rescan button and the
// theme toggle are RETIRED with their dead CSS (.chip/.ic.spinning); what
// remains is the logo + title + subtitle. The theme stays system-following
// (setThemeMode('system'), bootTheme in App.vue); recovery from a dead server
// stays covered by the steady 10 s poll loop + the error card's Retry button.
import { MiuixTopAppBar } from 'miuix-vue'
</script>
<template>
  <MiuixTopAppBar title="Task Files Explorer" subtitle="Miuix · download/ + archive/ dashboard">
    <template #navigation>
      <span class="appbar-logo" aria-hidden="true"><svg class="ic"><use href="#i-logo"/></svg></span>
    </template>
  </MiuixTopAppBar>
</template>
