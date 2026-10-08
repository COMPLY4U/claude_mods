export type Zeile = string | null

declare module 'claude-code' {
  interface PluginState {
    kontextanzeige: { zeile: Zeile }
  }
}
