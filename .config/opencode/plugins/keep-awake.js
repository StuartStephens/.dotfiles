export const KeepAwake = async () => {
  let inhibitor = null

  const spawnInhibitor = () => {
    if (process.platform === 'darwin') {
      return Bun.spawn(['caffeinate', '-d', '-i'], {
        stdin: 'ignore',
        stdout: 'ignore',
        stderr: 'ignore',
      })
    }

    if (process.platform === 'linux') {
      return Bun.spawn(
        [
          'systemd-inhibit',
          '--what=idle:sleep',
          '--why=OpenCode active',
          '--mode=block',
          'sleep',
          'infinity',
        ],
        {
          stdin: 'ignore',
          stdout: 'ignore',
          stderr: 'ignore',
        },
      )
    }

    return null
  }

  const start = () => {
    if (inhibitor) return
    try {
      inhibitor = spawnInhibitor()
      inhibitor?.unref?.()
    } catch (_) {
      inhibitor = null
    }
  }

  const stop = () => {
    if (!inhibitor) return
    try {
      inhibitor.kill()
    } catch (_) {}
    inhibitor = null
  }

  return {
    event: async ({ event }) => {
      const type = event?.type

      if (type === 'session.status') {
        const status = event.properties?.status?.type
        if (status === 'busy') {
          start()
        } else if (status === 'idle' || status === 'error') {
          stop()
        }
        return
      }

      if (type === 'session.idle' || type === 'session.error' || type === 'session.deleted') {
        stop()
      }
    },
  }
}
