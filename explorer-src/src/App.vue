<script setup>
// explorer UI v5.0 — Task Files Explorer, fully migrated to miuix-vue (Task 53):
// TopAppBar / IconButton / Dialog / SnackbarHost / FloatingActionButton + theme
// system are REAL miuix-vue components; D10 structures (4 tiles w/ official
// Material Icons, task rail, compact 40px search, compact 14/12/11px type,
// no hero/bento) and the whole v4.3.1/v4.4 behavioral engine are ported verbatim.
import { onMounted, ref } from 'vue'
import { MiuixSnackbarHost } from 'miuix-vue'
import IconSprite from './components/IconSprite.vue'
import TopBar from './components/TopBar.vue'
import StatsTiles from './components/StatsTiles.vue'
import TaskRail from './components/TaskRail.vue'
import Toolbar from './components/Toolbar.vue'
import FileList from './components/FileList.vue'
import PreviewModal from './components/PreviewModal.vue'
import FabTop from './components/FabTop.vue'
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
    <StatsTiles/>
    <TaskRail/>
    <Toolbar/>
    <FileList @preview="f => modal && modal.open(f)"/>
  </main>
  <footer>
    Served by the <b>dev.sh</b> boot hook → <b>explorer.py</b> at 127.0.0.1:3000 — upstream of the platform preview ingress.<br>
    <b>miuix-vue (HyperOS)</b> components · palette verbatim from compose-miuix-ui/miuix Colors.kt · system-adaptive theme (setThemeMode('system')) · server-side search &amp; pagination (v1.6) · UI v5.0 · single-file zero-runtime-dependency build · <span id="ftInfo">{{ ui.footer }}</span>
  </footer>
  <FabTop/>
  <PreviewModal ref="modal"/>
  <MiuixSnackbarHost/>
</template>
