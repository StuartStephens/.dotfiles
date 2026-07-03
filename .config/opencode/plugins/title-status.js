// Sets WezTerm tab title with colored status tokens driven by opencode session events.
// Includes the auto-generated thread title when available.
// Only active when WEZTERM_PANE is set (i.e. running inside WezTerm).

export const TitleStatus = async ({ $, directory }) => {
  const project = directory.split('/').filter(Boolean).pop() || 'opencode'
  const pane = process.env.WEZTERM_PANE

  // Match opencode's isDefaultTitle() — placeholder until the model generates a real one
  const isDefaultTitle = (title) =>
    /^(New session - |Child session - )\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(title)

  const setTitle = async (token) => {
    if (!pane) return
    const label =
      currentTitle && !isDefaultTitle(currentTitle) ? 'OC | ' + currentTitle : project
    try {
      await $`wezterm cli set-tab-title ${token + ' ' + label}`
    } catch (_) {}
  }

  let lastSessionStatus = 'done'
  let currentTitle = null

  return {
    event: async ({ event }) => {
      const type = event?.type

      // Capture the thread title whenever a session is created or updated
      if (type === 'session.updated' || type === 'session.created') {
        const title = event.properties?.info?.title
        if (title) {
          currentTitle = isDefaultTitle(title) ? null : title
          // Re-render with the new title, keeping current status
          await setTitle('[oc:' + lastSessionStatus + ']')
        }
        return
      }

      if (type === 'session.status') {
        const st = event.properties?.status?.type
        if (st === 'busy') {
          lastSessionStatus = 'working'
          await setTitle('[oc:working]')
        } else if (st === 'idle') {
          lastSessionStatus = 'done'
          await setTitle('[oc:done]')
        } else if (st === 'error') {
          lastSessionStatus = 'error'
          await setTitle('[oc:error]')
        }
      } else if (type === 'permission.asked') {
        await setTitle('[oc:waiting]')
      } else if (type === 'permission.replied') {
        await setTitle('[oc:' + lastSessionStatus + ']')
      }
    },
  }
}
