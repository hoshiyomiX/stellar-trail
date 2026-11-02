<script setup>
// explorer UI v5.0 (Task 62 amend, ref #61) — Task Files Explorer, fully
// migrated to miuix-vue (Task 53). Task 61 retired the body chrome on the
// owner order "hapus semua button & label di bawah 'Task File Manager'";
// Task 62 corrects the scope on the owner's clarification ("'below" means the
// contents of the top bar (clock/version chip/Rescan/Theme)"): those 4 appbar
// items are retired instead, and the dashboard card tiles the order never
// meant — StatsTiles (Dashboard, renamed from Release Health at Task 63) +
// TaskRail (Task History) — are
// REVERTED to their pre-Task-61 form. Toolbar (filter/search), FabTop, the
// footer and the listhead rootline stay retired (not card tiles; the
// "search restore" residual was offered at Task 61 and not taken).
// The clock interval is gone with the clock chip (no per-second tick for an
// unrendered label); the theme stays system-following via bootTheme.
import { onMounted, ref } from 'vue'
import { MiuixSnackbarHost } from 'miuix-vue'
import IconSprite from './components/IconSprite.vue'
import TopBar from './components/TopBar.vue'
import StatsTiles from './components/StatsTiles.vue'
import TaskRail from './components/TaskRail.vue'
import FileList from './components/FileList.vue'
import PreviewModal from './components/PreviewModal.vue'
import { ui, boot } from './explorer.js'
import { bootTheme } from './theme.js'

const modal = ref(null)

onMounted(() => {
  bootTheme(t => { ui.themeDark = (t === 'dark') })
  boot()                                                    /* engine boot: static detection, guarded poll, first list, watchdog */
})
</script>
<template>
  <IconSprite/>
  <TopBar/>
  <main>
    <StatsTiles/>
    <TaskRail/>
    <FileList @preview="f => modal && modal.open(f)"/>
  </main>
  <PreviewModal ref="modal"/>
  <MiuixSnackbarHost/>
</template>
