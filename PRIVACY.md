# Privacy

The KnobDeck plug-in for Lightroom Classic:

- **collects nothing and sends nothing to the internet.** It has no analytics, no telemetry and no
  crash reporting. It opens two ports on `localhost` only (58770 and 58771 unless you change
  them), which programs on other computers can't reach.
- **answers only the KnobDeck you allowed**: the first message on every connection must carry the
  pairing token you allowed in Lightroom's dialog; anything else is refused.
- **tells KnobDeck only what its keys show**: the current module, the selected photo's file name,
  flag, rating and colour label, and the values of the Develop settings. That goes no further than
  KnobDeck on the same computer. Photos, previews, metadata and the catalog stay in Lightroom.
- **stores only** the allowed pairing token and the two port numbers, in this plug-in's Lightroom
  preferences. **File ▸ Plug-in Manager ▸ KnobDeck ▸ Forget KnobDeck** removes the token.

For KnobDeck itself see the [KnobDeck privacy policy](https://knobdeck.harshalkudale.com/legal/privacy).
Questions: support@harshalkudale.com.
