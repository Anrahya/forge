---
name: unslop
description: "Use on any prose before it ships, such as replies, task.md, report.md, PR bodies, commit messages, and code comments, to remove AI writing tells."
user-invocable: true
---

# Unslop

Scan the text for each rule below, then rewrite. Keep the meaning and every fact. Rule numbers are stable ids that other files and gate G12 cite. Never renumber a rule. A retired rule leaves a gap.

Text inside inline code spans and fenced code blocks is exempt. Put a literal use of a listed word in backticks, such as the `_` character called underscore or a `landscape` screen orientation.

## Chat habits

1. Chatbot phrases. Delete openers, closers, and offers such as the phrase list below.
2. Sycophancy. Delete praise of the user or the question and any agreement given before the analysis. Answer directly.
3. Filler. Write "to" for "in order to", "because" for "due to the fact that", and "now" for "at this point in time". Delete "it is important to note that" and "it is worth mentioning that".
4. Hedging. Use one qualifier at most. When you are not sure, write "guess" and name the check that would settle it.
5. Generic conclusions. Delete closing lines such as "overall, this is a solid improvement". End on a fact, a next step, or nothing.
6. Trailing -ing clauses. Delete tails such as ", ensuring reliability" or ", highlighting the need for". If the point matters, give it its own sentence with a subject.

## Words

7. AI vocabulary. Replace each word in the vocabulary list below with a plain word, or delete it.
8. Fancy ways to say "is". Write "is" or "has" for "serves as", "stands as", "acts as", "functions as", "represents", "boasts", and "features".
9. "Not just X but Y". State Y. This covers "not only X but also Y" and "it's not X, it's Y".
10. Forced rule of three. Use the number of items that exist. Two is fine. Four is fine.
11. Plain word over fancy. Write "use" for "utilize", "help" for "facilitate", "many" for "numerous", "if" for "in the event that", "start" for "commence", "before" for "prior to", and "then" for "subsequently".
12. Abstract metaphor nouns. Replace substrate, vector, north star, flywheel, wedge, locus, nexus, bedrock, paradigm, modality, and primitive as a vague noun with the concrete thing. Literal technical senses are fine.
13. Adverbs. Cut them, or replace the verb and adverb with a stronger verb or a number. "Significantly faster" becomes the measured delta.

## Punctuation and layout

14. Em dashes. Do not use the em dash character, U+2014, anywhere. Use a period or a comma. Do not substitute an en dash or a double hyphen.
15. Colon as connector. Use a colon only before a list, an example, or a code block. Otherwise split the sentence.
16. Inline-header lists. A list item that opens with a bold label and a colon, then restates the label, is a tell. Write plain sentences or a plain list instead.
17. Title case headings. Use sentence case. Capitalize only the first word and proper nouns.
18. Decorative emoji. Remove emoji from headings, list items, and prose.

## Sentences

19. Say what it does, not how it feels. Replace "the API feels natural" with the mechanism or a number. If the sentence could appear unchanged in another project's docs, cut it.
20. One idea per sentence. When a reader has to reread a sentence, split it or drop a clause.
21. Active voice. Name the actor. "The file is parsed by the loader" becomes "the loader parses the file". Keep the passive only when the actor is unknown or does not matter.
22. Over-compression. Restore dropped articles and verbs, and spell out arrows, symbols, and private abbreviations. "Bad date → exit 2" becomes "a bad date makes the parser exit with code 2".

## Rule 7 vocabulary list

G12 matches these case-insensitively as whole words. The list includes the inflected forms it checks.

```
additionally
bolster bolstered bolstering bolsters
captivating
commendable
comprehensive
crucial crucially
cutting-edge
deep-dive
delve delved delves delving
embark embarked embarking embarks
empower empowered empowering empowers
endeavor endeavors endeavour endeavours
enduring
enhance enhanced enhancement enhancements enhances enhancing
ever-evolving
foster fostered fostering fosters
furthermore
game-changer game-changing
garner garnered garnering garners
groundbreaking
holistic holistically
interplay
intricacies intricate
invaluable
landscape landscapes
leverage leveraged leverages leveraging
meticulous meticulously
moreover
multifaceted
myriad
notably
nuanced
paramount
pivotal
plethora
realm realms
resonate resonated resonates resonating
revolutionary revolutionize revolutionized revolutionizes
robust robustly robustness
seamless seamlessly
showcase showcased showcases showcasing
spearhead spearheaded spearheading spearheads
streamline streamlined streamlines streamlining
synergy synergies
tapestry
testament
transformative
underscore underscored underscores underscoring
unparalleled
utilize utilized utilizes utilizing utilization
vibrant
vital
```

## Rule 1 phrase list

G12 matches these case-insensitively anywhere in a line.

```
i hope this helps
hope this helps
let me know if
feel free to
happy to help
i'd be happy to
great question
you're absolutely right
absolutely!
certainly!
of course!
as an ai
i apologize for
```

G12 also fails on a sentence that starts with "Let me".

## What G12 checks

G12 lints `report.md` and PR prose. It fails on rule 1 phrases, rule 7 words, rule 9 patterns, any rule 14 em dash, and rule 16 list items that open with bold text ending in a colon. The other rules are for the writer and the reviewer, because no regex judges them well.
