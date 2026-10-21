// The canvas's own words (Hakushi.Messages), with their placeholders and
// plural forms.

export class Messages {
  private plurals: Intl.PluralRules;

  constructor(
    private words: Record<string, string>,
    locale: string,
  ) {
    let rules: Intl.PluralRules;
    try {
      rules = new Intl.PluralRules(locale);
    } catch {
      rules = new Intl.PluralRules("en");
    }
    this.plurals = rules;
  }

  /** The words of `key`, with `{name}` placeholders filled. */
  t(key: string, values: Record<string, string | number> = {}): string {
    const text = this.words[key] ?? key;
    return text.replace(/\{(\w+)\}/g, (match, name: string) => (name in values ? String(values[name]) : match));
  }

  /** The words of `keyOne` or `keyOther` for a count `n`. */
  count(key: string, n: number, values: Record<string, string | number> = {}): string {
    const form = this.plurals.select(n) === "one" ? "One" : "Other";
    return this.t(key + form, { n, ...values });
  }
}
