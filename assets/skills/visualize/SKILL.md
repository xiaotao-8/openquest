---
name: visualize
description: Create a native interactive calculator, conditional form, chart or data table when local input changes help answer the user. Also handles repairs to an existing OpenQuest interface.
---

# Interactive answers

1. Choose a small native interface when the user benefits from changing inputs,
   comparing values or exploring supplied data. Use prose for a single fact or
   explanation without useful interaction. State a useful conclusion outside
   the interface.
2. Read `references/protocol.md`. Read `references/content.md` for layout and
   text; `references/inputs.md` for controls, validation and actions;
   `references/data.md` for charts/tables; `references/functions.md` when computing.
   Read `references/examples.md` for three complete, validated patterns.
3. Emit one top-level `openquest-ui` fence using the advertised header, complete
   single-line declarations and an explicit root. Never call a tool or function
   named `visualize` — no such tool exists; the interface is ordinary reply
   text inside the fence, nothing else. When the user asks for a card, emit
   the complete fence — never describe the card in prose or write a
   placeholder sentence in its place; a card exists only inside the fence.
   Keep all requested controls
   reachable from root and derive results from their bindings. Styling belongs
   to the app's theme; select only catalog semantics.
   Hard rules — the renderer rejects the whole block otherwise:
   - States, derived values and nodes share ONE namespace: never declare the
     same name twice, with or without the `$` prefix (no `$form` state next
     to a `form` node).
   - State declarations must be typed: `$name: number|string|boolean = value`.
     No untyped declarations and no array/record state; put option lists
     inline in the component (e.g. RadioGroup options) or in a `let`.
   - No string concatenation anywhere (`+` between strings is forbidden).
     Show dynamic results with separate Text nodes or catalog functions.
   - Text displays use `text=`.
   Minimal valid pattern (a voting card — copy the shape, change the labels):
   ```openquest-ui
   ui 1 catalog "openquest.native/1"
   $choice: string = "A"
   root = Column(children=[intro,form,ask])
   intro = Text(text="夏日新口味投票", variant="caption")
   form = Form(children=[voteGroup])
   voteGroup = RadioGroup(label="选一款你最想尝鲜的口味", bind=$choice, options=[{"value":"A","label":"青岚浮雪"},{"value":"B","label":"暮色柑橘"},{"value":"C","label":"薄荷撞云"}], required=true)
   ask = Button(label="提交投票", form=form, action=Ask(text="我选了这款口味", context={"choice":$choice}))
   ```
4. Check unique names, allowed properties, required fields, units, mappings and
   every referenced ID before closing the fence. Test the reasoning for changed
   inputs, not just initial values. Hidden fields retain values but do not block
   form validation. Ask creates an editable draft; it never sends automatically.
   Check every number, sample count and trend in the surrounding prose against
   those same expressions and records. Use the full sample grid, including
   fractional coordinates and missing values. A trend must agree with every
   relevant row; distinguish user-set parameters from calculated results.
   Prefer a short explanation of the controls and data mapping over additional
   numerical interpretations the user did not request.
5. For an answer that displays a dataset or calculated result, include a visible
   provenance sentence in the prose or a Text/Callout. Label supplied synthetic
   rows, invented numbers and mathematical demonstrations as "Synthetic example
   data" in the user's language. Keep this label when copying supplied values
   unchanged. For real user data, identify its supplied source instead. Finish
   only after this qualification appears in the visible answer, outside code.

For repairs, preserve the user's intended behavior and correct the supplied
bounded diagnostics/source. Return a complete corrected interface with a short
explanation. The repair draft is ordinary editable chat text, not a tool call.

Only when supported native components cannot express a self-contained interaction,
read `references/web.md`. Use native charts, calculators, forms and tables whenever
possible. Copy/read-aloud behavior is described in `references/semantics.md`.
