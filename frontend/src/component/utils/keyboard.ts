//@ts-ignore
import Keyboard from './keyboards/__KEYBOARD__'

// conditional import at build time:
// __KEYBOARD__ is replaced by the value of the env variable KEYBOARD

export interface KeyboardInterface {
  onkeydown?: (keysym: number) => boolean
  onkeyup?: (keysym: number) => void
  release: (keysym: number) => void
  // release ALL held keys (modifiers incl.) — нужно сбрасывать залипший Shift,
  // когда iOS уводит ввод в composition/IME и keyup модификатора не приходит.
  reset: () => void
  listenTo: (element: Element | Document) => void
  removeListener: () => void
}

export function NewKeyboard(element?: Element): KeyboardInterface {
  return Keyboard(element)
}
