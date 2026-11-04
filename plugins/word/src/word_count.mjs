/** Explicit, read-only document snapshot utility. Never runs on an edit event. */
export function countWords(text, maxCodePoints = 1_000_000) {
  if (typeof text !== 'string') throw new TypeError('text must be a string')
  const characters = Array.from(text)
  if (characters.length > maxCodePoints) throw new RangeError('TEXT_BUDGET_EXCEEDED')
  const han = (text.match(/\p{Script=Han}/gu) ?? []).length
  const otherWords = (text.match(/[\p{L}\p{N}]+(?:['’_-][\p{L}\p{N}]+)*/gu) ?? [])
    .filter(token => !/\p{Script=Han}/u.test(token)).length
  return {
    profile: 'word.count.v1',
    characters: characters.length,
    charactersNoWhitespace: characters.filter(ch => !/\s/u.test(ch)).length,
    words: han + otherWords,
    paragraphs: text.length === 0 ? 0 : text.split(/\r\n|\r|\n/u).length
  }
}
