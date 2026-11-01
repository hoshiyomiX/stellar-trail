// explorer UI v5.0 — snackbar bridge: the v4.4 custom .snackbar element is
// replaced by the real miuix-vue SnackbarHost + showSnackbar (Task 53).
// Same contract as the old snack(): message, optional action label + action fn, 5 s auto-hide.
import { showSnackbar } from 'miuix-vue'

export function snack(msg, actLabel, actFn){
  const p = showSnackbar({
    message: msg,
    duration: 5000,                        /* the v4.4 timer */
    actionLabel: actLabel || undefined,
  });
  if(actLabel && actFn) p.then(r=>{ if(r==='action') actFn(); });
}
