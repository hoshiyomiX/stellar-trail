<script setup>
// explorer UI v5.0 (Task 61 amend) — Task Files Explorer, fully migrated to
// miuix-vue (Task 53): TopAppBar / IconButton / Dialog / SnackbarHost + theme
// system are REAL miuix-vue components. Task 61 (owner order "hapus semua
// button & label di bawah 'Task File Manager'. They're useless"): the body
// chrome is RETIRED — StatsTiles (Release Health), TaskRail (Task History),
// Toolbar (filter/search) and FabTop (back-to-top) + the footer are GONE;
// what remains is the appbar (identity + Rescan/Theme), the file list, and
// the preview modal. D10's structure locks (rail + 4 tiles) are amended by
// this explicit owner order.
import { onMounted, ref } from 'vue'
import { MiuixSnackbarHost } from 'miuix-vue'
import IconSprite from './components/IconSprite.vue'
import TopBar from './components/TopBar.vue'
import FileList from './components/FileList.vue'
import PreviewModal from './components/PreviewModal.vue'
import { ui, boot } from './explorer.js'
import { bootTheme } from './theme.js'

const modal = ref(null)

onMounted(() => {
  bootTheme(t => { ui.themeDark = (t === 'dark') })
  boot()                                                    /* engine boot: static detection, guarded poll, first list, watchdog */
  setInterval(() => { ui.clock = new Date().toLocaleTimeString('en-US') }, 1000)
})
</script>
<template>
  <IconSprite/>
  <TopBar/>
  <main>
    <FileList @preview="f => modal && modal.open(f)"/>
  </main>
  <PreviewModal ref="modal"/>
  <MiuixSnackbarHost/>
</template>
