// ScreenBar Halo 2 card for Home Assistant: https://github.com/rchen14b/screenbar-halo2-companion
//
// On the dashboard: one compact tile (white with a yellow icon while on, a brightness fill,
// "On · 30% · 4000 K", an Auto chip while Auto brightness is on). Tapping the icon toggles the lamp;
// tapping the tile opens a drawer laid out like BenQ's iScreenBar app: Power, Auto, Front and Back;
// a brightness slider for each lit section; colour temperature; the presence timeout.
//
// It drives the lamp through the entities of the ESPHome bridge from
// https://github.com/NickCao/benq-screenbar-halo2-esphome. Sliders send when released, so a drag is
// one radio command.
//
//   type: custom:screenbar-halo2-card
//   entity: light.screenbar
//   name: ScreenBar               # optional
// The other entities default to the light's object ID (screenbar) and can be overridden:
//   lighting_mode, ultrasonic, auto_brightness, front_brightness, back_brightness, radio_status
// auto_brightness defaults to switch.<id>_auto_brightness if the bridge has one (on/off, following
// the lamp), else to the bridge's button.<id>_auto_brightness (starts Auto).
//
// Optional theme variables: --screenbar-card-active-surface, --screenbar-card-active-ink,
// --screenbar-card-active-fill, --screenbar-card-active-icon-background,
// --screenbar-card-active-icon-color.

const DEFAULTS = {
  lighting_mode: (id) => `select.${id}_lighting_mode`,
  ultrasonic: (id) => `select.${id}_ultrasonic_sensor`,
  front_brightness: (id) => `number.${id}_front_brightness`,
  back_brightness: (id) => `number.${id}_back_brightness`,
  radio_status: (id) => `sensor.${id}_radio_status`,
};

const STYLE = `
  :host { display: block; height: 100%; --accent: var(--screenbar-card-active-icon-background, rgb(255, 204, 0)); }
  button { font: inherit; color: inherit; border: 0; background: none; padding: 0; cursor: pointer; }

  /* Compact tile */
  ha-card.tile {
    position: relative; box-sizing: border-box; height: 100%; min-height: 56px; overflow: hidden;
    display: flex; align-items: center; gap: 10px; padding: 0 12px 0 9px; cursor: pointer;
  }
  ha-card.tile.on {
    background: var(--screenbar-card-active-surface, rgba(255, 255, 255, 0.9)) !important;
    color: var(--screenbar-card-active-ink, #1d1d1f);
  }
  ha-card.tile.on::before { display: none; }
  .fill {
    position: absolute; inset: 0 auto 0 0; width: var(--level, 0%); pointer-events: none;
    background: var(--screenbar-card-active-fill, #fff); opacity: 0; transition: width 240ms ease;
  }
  ha-card.tile.on .fill { opacity: 1; }
  .tile-icon {
    position: relative; width: 38px; height: 38px; flex-shrink: 0; border-radius: 50%; display: grid; place-items: center;
    background: var(--bubble-icon-background-color, rgba(127, 127, 127, 0.14)); color: var(--primary-text-color);
  }
  ha-card.tile.on .tile-icon { background: var(--accent); color: var(--screenbar-card-active-icon-color, #fff); }
  .tile-icon ha-icon { --mdc-icon-size: 22px; }
  .tile-text { position: relative; flex: 1; min-width: 0; display: flex; flex-direction: column; }
  .tile-name { font-size: 14px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .tile-state { font-size: 12px; opacity: 0.7; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .chip {
    position: relative; display: none; align-items: center; gap: 3px; padding: 3px 8px 3px 5px; border-radius: 999px;
    font-size: 11px; font-weight: 600; background: rgba(255, 159, 10, 0.16); color: rgb(214, 120, 0);
  }
  .chip.show { display: inline-flex; }
  .chip ha-icon { --mdc-icon-size: 15px; }
  .tile-chevron { position: relative; --mdc-icon-size: 18px; opacity: 0.45; }
  ha-card.tile.unavailable { opacity: 0.5; }

  /* Drawer: a modal sheet, centred on wide screens and docked to the bottom on phones. */
  dialog {
    width: min(92vw, 400px); max-height: 90vh; box-sizing: border-box; padding: 18px 20px 20px;
    border: 0; border-radius: 28px; color: var(--primary-text-color);
    background: var(--frosted-glass-popup-surface, var(--card-background-color));
    backdrop-filter: blur(24px) saturate(1.4); -webkit-backdrop-filter: blur(24px) saturate(1.4);
    box-shadow: 0 24px 60px rgba(0, 0, 0, 0.3);
  }
  dialog::backdrop { background: rgba(0, 0, 0, 0.35); backdrop-filter: blur(4px); -webkit-backdrop-filter: blur(4px); }
  dialog[open] { animation: rise 220ms ease-out; }
  @keyframes rise { from { transform: translateY(16px); opacity: 0; } }
  @media (max-width: 600px) {
    dialog { margin: auto 0 0; width: 100vw; max-width: 100vw; border-radius: 28px 28px 0 0; padding-bottom: 28px; }
  }
  /* The drawer focuses the panel on open, so no button starts with a focus ring. */
  .panel { display: flex; flex-direction: column; gap: 16px; outline: none; }
  dialog button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
  .panel.unavailable > :not(.header) { opacity: 0.45; pointer-events: none; }
  .header { display: flex; align-items: center; gap: 6px; }
  .title { flex: 1; min-width: 0; display: flex; align-items: baseline; gap: 8px; }
  .name { font-size: 16px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .status { font-size: 12px; color: var(--secondary-text-color); white-space: nowrap; }
  .status.warn { color: var(--warning-color, #ff9f0a); }
  .icon-button {
    width: 32px; height: 32px; border-radius: 16px; display: grid; place-items: center; color: var(--secondary-text-color);
    background: rgba(127, 127, 127, 0.12);
  }
  .icon-button ha-icon { --mdc-icon-size: 19px; }

  .rounds { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; justify-items: center; }
  .round { display: flex; flex-direction: column; align-items: center; gap: 6px; font-size: 11px; color: var(--secondary-text-color); }
  .round .disc {
    width: 54px; height: 54px; border-radius: 50%; display: grid; place-items: center;
    background: var(--bubble-sub-button-background-color, rgba(127, 127, 127, 0.14));
    color: var(--primary-text-color); transition: background 160ms ease, color 160ms ease, transform 120ms ease;
  }
  .round .disc ha-icon { --mdc-icon-size: 24px; }
  .round:active .disc { transform: scale(0.94); }
  .round.on .disc {
    background: var(--screenbar-card-active-surface, rgba(255, 255, 255, 0.9));
    color: rgb(255, 159, 10); box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
  }
  .round.on { color: var(--primary-text-color); }

  .slider { display: grid; grid-template-columns: 20px 1fr 20px; align-items: center; gap: 10px; }
  .slider ha-icon { --mdc-icon-size: 18px; color: var(--secondary-text-color); justify-self: center; }
  .slider .small { --mdc-icon-size: 14px; }
  .caption { display: flex; justify-content: space-between; font-size: 12px; color: var(--secondary-text-color); margin: -10px 30px 0; }
  .caption b { font-weight: 600; color: var(--primary-text-color); }
  input[type="range"] {
    -webkit-appearance: none; appearance: none; width: 100%; height: 28px; margin: 0; background: transparent; cursor: pointer;
  }
  input[type="range"]::-webkit-slider-runnable-track { height: 6px; border-radius: 3px; background: var(--track); }
  input[type="range"]::-moz-range-track { height: 6px; border-radius: 3px; background: var(--track); }
  input[type="range"]::-webkit-slider-thumb {
    -webkit-appearance: none; width: 22px; height: 22px; margin-top: -8px; border-radius: 50%;
    background: #fff; box-shadow: 0 1px 4px rgba(0, 0, 0, 0.3);
  }
  input[type="range"]::-moz-range-thumb { width: 22px; height: 22px; border: 0; border-radius: 50%; background: #fff; box-shadow: 0 1px 4px rgba(0, 0, 0, 0.3); }
  .level { --track: linear-gradient(90deg, var(--accent) var(--pct, 0%), rgba(127, 127, 127, 0.22) var(--pct, 0%)); }
  .kelvin { --track: linear-gradient(90deg, #ffa94d, #ffd9a8 30%, #fff6ea 55%, #e3eeff 80%, #bcd4ff); }

  .pills { display: grid; grid-template-columns: 1fr; gap: 10px; }
  .pill {
    display: flex; align-items: center; gap: 10px; padding: 8px 12px 8px 8px; border-radius: 999px; min-width: 0; text-align: left;
    background: var(--bubble-sub-button-background-color, rgba(127, 127, 127, 0.14));
  }
  .pill.on { background: var(--screenbar-card-active-surface, rgba(255, 255, 255, 0.9)); color: var(--screenbar-card-active-ink, #1d1d1f); }
  .pill .icon { width: 34px; height: 34px; flex-shrink: 0; border-radius: 50%; display: grid; place-items: center; background: rgba(127, 127, 127, 0.16); }
  .pill.on .icon { background: var(--accent); color: var(--screenbar-card-active-icon-color, #fff); }
  .pill .icon ha-icon { --mdc-icon-size: 18px; }
  .pill .text { flex: 1; min-width: 0; display: flex; flex-direction: column; }
  .pill .label { font-size: 13px; font-weight: 600; }
  .pill .value { font-size: 12px; opacity: 0.7; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .pill .chevron { --mdc-icon-size: 18px; opacity: 0.5; }

  /* Brightness sliders show only for lit sections; faded while the lamp is off. */
  .panel [hidden] { display: none; }
  .dim { opacity: 0.5; }

  /* Presence menu: a popover above the drawer. */
  .menu {
    position: fixed; inset: auto; margin: 0; padding: 6px; border: 0; border-radius: 16px; min-width: 170px;
    color: var(--primary-text-color); background: var(--frosted-glass-popup-surface, var(--card-background-color));
    backdrop-filter: blur(18px) saturate(1.4); -webkit-backdrop-filter: blur(18px) saturate(1.4);
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.18);
  }
  .menu button { display: flex; width: 100%; align-items: center; gap: 8px; padding: 9px 10px; border-radius: 10px; font-size: 14px; }
  .menu button:hover { background: rgba(127, 127, 127, 0.14); }
  .menu ha-icon { --mdc-icon-size: 18px; visibility: hidden; color: rgb(255, 159, 10); }
  .menu button.current ha-icon { visibility: visible; }
`;

const TEMPLATE = `
  <ha-card class="tile" role="button" tabindex="0" aria-haspopup="dialog">
    <div class="fill"></div>
    <button class="tile-icon" title="Turn on or off"><ha-icon icon="mdi:wall-sconce-flat"></ha-icon></button>
    <div class="tile-text"><span class="tile-name"></span><span class="tile-state"></span></div>
    <span class="chip" title="Auto brightness is on"><ha-icon icon="mdi:brightness-auto"></ha-icon>Auto</span>
    <ha-icon class="tile-chevron" icon="mdi:chevron-right"></ha-icon>
  </ha-card>
  <dialog aria-label="ScreenBar controls">
    <div class="panel" tabindex="-1" autofocus>
      <div class="header">
        <div class="title"><span class="name"></span><span class="status"></span></div>
        <button class="icon-button more" title="Details"><ha-icon icon="mdi:dots-horizontal"></ha-icon></button>
        <button class="icon-button close" title="Close"><ha-icon icon="mdi:close"></ha-icon></button>
      </div>
      <div class="rounds">
        <button class="round power" title="Power"><span class="disc"><ha-icon icon="mdi:power"></ha-icon></span>Power</button>
        <button class="round auto" title="Auto brightness"><span class="disc"><ha-icon icon="mdi:brightness-auto"></ha-icon></span>Auto</button>
        <button class="round front" title="Front light"><span class="disc"><ha-icon icon="mdi:lightbulb-on-outline"></ha-icon></span>Front</button>
        <button class="round back" title="Back light"><span class="disc"><ha-icon icon="mdi:wall-sconce-flat-outline"></ha-icon></span>Back</button>
      </div>
      <div class="slider level front-level">
        <ha-icon class="small" icon="mdi:brightness-5"></ha-icon>
        <input type="range" min="1" max="100" step="1" aria-label="Front brightness">
        <ha-icon icon="mdi:brightness-7"></ha-icon>
      </div>
      <div class="caption front-level"><span>Front brightness</span><b></b></div>
      <div class="slider level back-level">
        <ha-icon class="small" icon="mdi:brightness-5"></ha-icon>
        <input type="range" min="1" max="100" step="1" aria-label="Back brightness">
        <ha-icon icon="mdi:brightness-7"></ha-icon>
      </div>
      <div class="caption back-level"><span>Back brightness</span><b></b></div>
      <div class="slider kelvin">
        <ha-icon class="small" icon="mdi:fire"></ha-icon>
        <input type="range" min="2700" max="6500" step="100" aria-label="Colour temperature">
        <ha-icon icon="mdi:snowflake"></ha-icon>
      </div>
      <div class="caption"><span>Colour temperature</span><b class="kelvin-value"></b></div>
      <div class="pills">
        <button class="pill presence">
          <span class="icon"><ha-icon icon="mdi:motion-sensor"></ha-icon></span>
          <span class="text"><span class="label">Presence</span><span class="value"></span></span>
          <ha-icon class="chevron" icon="mdi:chevron-right"></ha-icon>
        </button>
      </div>
    </div>
  </dialog>
  <div class="menu" popover="auto"></div>`;

class ScreenBarHalo2Card extends HTMLElement {
  setConfig(config) {
    if (!config.entity || !config.entity.startsWith("light.")) throw new Error("entity: a light is required");
    const id = config.entity.slice("light.".length);
    this._config = { name: "ScreenBar" };
    for (const [key, make] of Object.entries(DEFAULTS)) this._config[key] = make(id);
    // Auto brightness: the bridge's switch if it has one, else its button (resolved in set hass).
    this._autoCandidates = config.auto_brightness
      ? [config.auto_brightness]
      : [`switch.${id}_auto_brightness`, `button.${id}_auto_brightness`];
    Object.assign(this._config, config);
    this._build();
  }

  set hass(hass) {
    this._hass = hass;
    this._config.auto_brightness = this._autoCandidates.find((id) => hass.states[id]) ?? this._autoCandidates[0];
    const ids = ["entity", "auto_brightness", ...Object.keys(DEFAULTS)].map((key) => this._config[key]);
    const states = ids.map((id) => hass.states[id]);
    if (this._last && states.every((s, i) => s === this._last[i])) return;
    this._last = states;
    this._render();
  }

  getCardSize() {
    return 1;
  }

  getGridOptions() {
    return { columns: 12, min_columns: 6, rows: 1, min_rows: 1 };
  }

  _build() {
    if (!this.shadowRoot) this.attachShadow({ mode: "open" });
    this.shadowRoot.innerHTML = `<style>${STYLE}</style>${TEMPLATE}`;
    const $ = (selector) => this.shadowRoot.querySelector(selector);
    this._el = {
      tile: $("ha-card.tile"), tileIcon: $(".tile-icon"), tileName: $(".tile-name"), tileState: $(".tile-state"),
      chip: $(".chip"), dialog: $("dialog"), panel: $(".panel"), name: $(".name"), status: $(".status"),
      power: $(".power"), auto: $(".auto"), front: $(".front"), back: $(".back"),
      kelvin: $(".kelvin input"), kelvinValue: $(".kelvin-value"),
      presence: $(".presence"), menu: $(".menu"),
      frontLevel: $(".front-level input"), frontValue: $(".caption.front-level b"),
      backLevel: $(".back-level input"), backValue: $(".caption.back-level b"),
      frontRows: this.shadowRoot.querySelectorAll(".front-level"),
      backRows: this.shadowRoot.querySelectorAll(".back-level"),
    };
    const e = this._el;

    // The tile: the icon toggles the lamp, anywhere else opens the drawer.
    e.tileIcon.addEventListener("click", (ev) => {
      ev.stopPropagation();
      this._call("light", "toggle", this._config.entity);
    });
    e.tile.addEventListener("click", () => this._openDrawer());
    e.tile.addEventListener("keydown", (ev) => {
      if (ev.key === "Enter" || ev.key === " ") {
        ev.preventDefault();
        this._openDrawer();
      }
    });
    // Clicking the backdrop (the dialog element itself, outside the panel) closes the drawer.
    e.dialog.addEventListener("click", (ev) => ev.target === e.dialog && e.dialog.close());
    $(".close").addEventListener("click", () => e.dialog.close());
    $(".more").addEventListener("click", () => {
      e.dialog.close();
      this._moreInfo(this._config.entity);
    });

    e.power.addEventListener("click", () => this._call("light", "toggle", this._config.entity));
    e.auto.addEventListener("click", () => this._toggleAuto());
    e.front.addEventListener("click", () => this._toggleSection("front"));
    e.back.addEventListener("click", () => this._toggleSection("back"));
    e.presence.addEventListener("click", () => this._openPresenceMenu());

    this._slider(e.kelvin, (v) => `${v} K`, e.kelvinValue, (v) =>
      this._call("light", "turn_on", this._config.entity, { color_temp_kelvin: v }));
    this._slider(e.frontLevel, (v) => `${v}%`, e.frontValue, (v) =>
      this._call("number", "set_value", this._config.front_brightness, { value: v }));
    this._slider(e.backLevel, (v) => `${v}%`, e.backValue, (v) =>
      this._call("number", "set_value", this._config.back_brightness, { value: v }));
  }

  _openDrawer() {
    if (!this._el.dialog.open) this._el.dialog.showModal();
  }

  // Labels follow the thumb while dragging; the service is called once, on release. Updates from HA
  // don't move a slider that is being dragged.
  _slider(input, format, label, send) {
    const show = () => {
      label.textContent = format(Number(input.value));
      input.parentElement.style.setProperty("--pct", `${((input.value - input.min) / (input.max - input.min)) * 100}%`);
    };
    input._show = show;
    input.addEventListener("input", () => {
      input._dragging = true;
      show();
    });
    input.addEventListener("change", () => {
      input._dragging = false;
      send(Number(input.value));
    });
  }

  _setSlider(input, value) {
    if (input._dragging || value === undefined || value === null || Number.isNaN(value)) return;
    input.value = value;
    input._show();
  }

  _autoOn() {
    const auto = this._hass.states[this._config.auto_brightness];
    return this._config.auto_brightness.startsWith("switch.") ? auto?.state === "on" : Boolean(this._autoFlash);
  }

  _render() {
    if (!this._hass || !this._el) return;
    const c = this._config;
    const e = this._el;
    const get = (id) => this._hass.states[id];
    const light = get(c.entity);
    e.tileName.textContent = c.name;
    e.name.textContent = c.name;

    const available = light && light.state !== "unavailable";
    e.tile.classList.toggle("unavailable", !available);
    e.panel.classList.toggle("unavailable", !available);
    this._renderStatus(available, get(c.radio_status));
    if (!available) {
      e.tile.classList.remove("on");
      e.tileState.textContent = "Unavailable";
      e.chip.classList.remove("show");
      return;
    }

    const on = light.state === "on";
    const attrs = light.attributes;
    const percent = attrs.brightness != null ? Math.max(1, Math.round(attrs.brightness / 2.55)) : null;
    const kelvin = attrs.color_temp_kelvin != null ? Math.round(attrs.color_temp_kelvin / 100) * 100 : null;
    const autoOn = this._autoOn();

    // Tile
    e.tile.classList.toggle("on", on);
    e.tile.style.setProperty("--level", `${on && percent ? percent : 0}%`);
    e.tileState.textContent = on ? ["On", percent && `${percent}%`, kelvin && `${kelvin} K`].filter(Boolean).join(" · ") : "Off";
    e.chip.classList.toggle("show", on && autoOn);

    // Drawer
    e.power.classList.toggle("on", on);
    e.auto.classList.toggle("on", autoOn);
    const mode = get(c.lighting_mode)?.state;
    const frontLit = mode === "Front" || mode === "Both";
    const backLit = mode === "Back" || mode === "Both";
    e.front.classList.toggle("on", frontLit);
    e.back.classList.toggle("on", backLit);

    // The lamp keeps a level per section and ignores the level of an unlit one, so there is a slider
    // for each lit section: one for Front or Back alone, both when both are lit.
    this._setSlider(e.frontLevel, Number(get(c.front_brightness)?.state));
    this._setSlider(e.backLevel, Number(get(c.back_brightness)?.state));
    for (const [rows, lit] of [[e.frontRows, frontLit], [e.backRows, backLit]]) {
      for (const row of rows) {
        row.hidden = !lit;
        row.classList.toggle("dim", !on);
      }
    }

    e.kelvin.min = attrs.min_color_temp_kelvin ?? 2700;
    e.kelvin.max = attrs.max_color_temp_kelvin ?? 6500;
    if (kelvin) this._setSlider(e.kelvin, kelvin);
    if (!on && kelvin == null && !e.kelvin._dragging) e.kelvinValue.textContent = "—";

    // "5 minutes" -> "5 min": the lamp turns off after that long without presence.
    const presence = get(c.ultrasonic)?.state;
    const presenceOn = presence && !["Disabled", "unknown", "unavailable"].includes(presence);
    e.presence.classList.toggle("on", Boolean(presenceOn));
    e.presence.querySelector(".value").textContent = presenceOn ? presence.replace(/minutes?/, "min") : "Off";
  }

  _renderStatus(available, radio) {
    const text = radio?.state ?? "";
    let label = text;
    let warn = false;
    if (!available) [label, warn] = ["Offline", true];
    else if (/lamp status received|controller update received/i.test(text)) label = "Synced";
    else if (/command sent/i.test(text)) label = "Sending…";
    else if (/discover/i.test(text)) label = "Pairing…";
    else if (/unavailable|error|fail/i.test(text)) warn = true;
    this._el.status.textContent = label;
    this._el.status.classList.toggle("warn", warn);
    this._el.status.title = text;
  }

  // A switch turns Auto on and off and shows what the lamp reports; a plain button only starts it.
  _toggleAuto() {
    const entity = this._config.auto_brightness;
    if (entity.startsWith("switch.")) {
      this._call("switch", "toggle", entity);
      return;
    }
    this._call("button", "press", entity);
    this._autoFlash = true;
    this._render();
    setTimeout(() => {
      this._autoFlash = false;
      this._render();
    }, 1200);
  }

  // Front and Back map onto the bridge's Lighting mode (Front, Back, Both); one section stays lit.
  _toggleSection(section) {
    const mode = this._hass.states[this._config.lighting_mode]?.state;
    const front = mode === "Front" || mode === "Both";
    const back = mode === "Back" || mode === "Both";
    const next = section === "front" ? [!front, back] : [front, !back];
    if (!next[0] && !next[1]) return;
    const option = next[0] && next[1] ? "Both" : next[0] ? "Front" : "Back";
    this._call("select", "select_option", this._config.lighting_mode, { option });
  }

  _openPresenceMenu() {
    const select = this._hass.states[this._config.ultrasonic];
    if (!select) return;
    const menu = this._el.menu;
    menu.replaceChildren(
      ...(select.attributes.options || []).map((option) => {
        const item = document.createElement("button");
        item.className = option === select.state ? "current" : "";
        item.innerHTML = `<ha-icon icon="mdi:check"></ha-icon><span></span>`;
        item.querySelector("span").textContent = option === "Disabled" ? "Off" : `Off after ${option}`;
        item.addEventListener("click", () => {
          menu.hidePopover();
          this._call("select", "select_option", this._config.ultrasonic, { option });
        });
        return item;
      })
    );
    menu.showPopover();
    const anchor = this._el.presence.getBoundingClientRect();
    const top = anchor.bottom + 6 + menu.offsetHeight > innerHeight ? anchor.top - menu.offsetHeight - 6 : anchor.bottom + 6;
    menu.style.left = `${Math.min(anchor.left, innerWidth - menu.offsetWidth - 8)}px`;
    menu.style.top = `${Math.max(8, top)}px`;
  }

  _call(domain, service, entityId, data = {}) {
    this._hass.callService(domain, service, { entity_id: entityId, ...data });
  }

  _moreInfo(entityId) {
    this.dispatchEvent(new CustomEvent("hass-more-info", { detail: { entityId }, bubbles: true, composed: true }));
  }
}

customElements.define("screenbar-halo2-card", ScreenBarHalo2Card);
window.customCards = window.customCards || [];
window.customCards.push({
  type: "screenbar-halo2-card",
  name: "ScreenBar Halo 2",
  description: "BenQ ScreenBar Halo 2: a compact tile that opens an iScreenBar-style control drawer.",
});
