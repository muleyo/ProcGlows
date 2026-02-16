<h1>muleyo's ProcGlows</h1>
<p>Add custom glow effects to your action buttons based on buffs, spell cooldowns, and usable items.</p>
<hr>
<h2>Features</h2>
<ul>
<li><strong>Aura Glows</strong> &mdash; Watch for a specific buff or proc (tracked by the CooldownManager) and make a target action button glow with a custom color.</li>
<li><strong>Spell Glows</strong> &mdash; Make an action button glow whenever a spell is off cooldown and usable.</li>
<li><strong>Item Glows</strong> &mdash; Make an action button glow when an item becomes usable.</li>
<li><strong>Custom Colors</strong> &mdash; Set a unique glow color for every entry individually.</li>
<li><strong>Hide Cast Animations</strong> &mdash; Optionally hide Blizzard's spell-cast, interrupt, and reticle overlay animations on action buttons.</li>
<li><strong>Full GUI</strong> &mdash; Add, edit, and remove entries through an in-game configuration panel. No manual editing required.</li>
</ul>
<h2>Slash Commands</h2>
<ul>
<li><code>/pg</code> or <code>/procglows</code> &mdash; Open the configuration window</li>
</ul>
<p>The settings panel is also available under <strong>Game Menu &rarr; Options &rarr; AddOns &rarr; ProcGlows</strong>.</p>
<hr>
<h2>How It Works</h2>
<h3>Auras</h3>
<p>Select the <strong>Buff/Proc</strong> you want to watch for from the dropdown menu and enter the <strong>Target Spell ID</strong> (the spell on your bar that should glow). The addon monitors the CooldownManager and lights up the corresponding button when the buff is active.</p>
<blockquote><strong>Note:</strong> Only buffs tracked by the CooldownManager appear in the dropdown. Use the <strong>BaseSpellID / Talent SpellID</strong>, not rank-specific or override spell IDs.</blockquote>
<h3>Spells</h3>
<p>Enter a <strong>Spell ID</strong> and the addon will glow its action button whenever the spell is usable (off cooldown, resources available, etc.).</p>
<h3>Items</h3>
<p>Enter an <strong>Item ID</strong> and the addon will glow its action button whenever the item is usable.</p>
<hr>
<h2>Feedback &amp; Bugs</h2>
<p>Found a bug or have a suggestion? Please open an issue on the project page!</p>
<hr>
<h2>Donate</h2>
<p>If you enjoy ProcGlows and would like to support development, consider <a href="https://pay.muleyo.dev/?donation=true">making a donation</a>. Thank you!</p>
