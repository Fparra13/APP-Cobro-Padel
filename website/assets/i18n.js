(function () {
  const STORAGE_KEY = "kloovi_lang";
  const SUPPORTED = ["es", "en", "pt"];

  function detectLang() {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved && SUPPORTED.includes(saved)) return saved;
    } catch (_) {}

    const nav = (navigator.languages && navigator.languages[0]) || navigator.language || "es";
    const lower = String(nav).toLowerCase();
    if (lower.startsWith("pt")) return "pt";
    if (lower.startsWith("en")) return "en";
    return "es";
  }

  function t(lang) {
    const pack = window.KLOOVI_LOCALES && window.KLOOVI_LOCALES[lang];
    return pack || window.KLOOVI_LOCALES.es;
  }

  function fill(el, value) {
    if (value == null) return;
    if (el.hasAttribute("data-i18n-html")) {
      el.innerHTML = value;
      return;
    }
    el.textContent = value;
  }

  function apply(lang) {
    const dict = t(lang);
    document.documentElement.lang = dict.htmlLang || lang;

    const page = document.body.getAttribute("data-page") || "home";
    if (page === "home") {
      document.title = dict.metaTitleHome;
      const meta = document.querySelector('meta[name="description"]');
      if (meta) meta.setAttribute("content", dict.metaDescHome);
    } else if (page === "privacy") {
      document.title = dict.metaTitlePrivacy;
      const meta = document.querySelector('meta[name="description"]');
      if (meta) meta.setAttribute("content", dict.metaDescPrivacy);
    } else if (page === "terms") {
      document.title = dict.metaTitleTerms;
      const meta = document.querySelector('meta[name="description"]');
      if (meta) meta.setAttribute("content", dict.metaDescTerms);
    } else if (page === "delete-account") {
      document.title = dict.metaTitleDeleteAccount;
      const meta = document.querySelector('meta[name="description"]');
      if (meta) meta.setAttribute("content", dict.metaDescDeleteAccount);
    }

    document.querySelectorAll("[data-i18n]").forEach((el) => {
      const key = el.getAttribute("data-i18n");
      let value = dict[key];
      if (typeof value === "string" && value.includes("{year}")) {
        value = value.replace("{year}", String(new Date().getFullYear()));
      }
      fill(el, value);
    });

    document.querySelectorAll("[data-i18n-html]").forEach((el) => {
      const key = el.getAttribute("data-i18n-html");
      fill(el, dict[key]);
    });

    document.querySelectorAll("[data-i18n-alt]").forEach((el) => {
      const key = el.getAttribute("data-i18n-alt");
      const value = dict[key];
      if (typeof value === "string") el.setAttribute("alt", value);
    });

    document.querySelectorAll("[data-i18n-src]").forEach((el) => {
      const key = el.getAttribute("data-i18n-src");
      const value = dict[key];
      if (typeof value === "string" && el.getAttribute("src") !== value) {
        el.setAttribute("src", value);
      }
    });

    document.querySelectorAll("[data-i18n-aria]").forEach((el) => {
      const key = el.getAttribute("data-i18n-aria");
      const value = dict[key];
      if (typeof value === "string") el.setAttribute("aria-label", value);
    });

    document.querySelectorAll("[data-i18n-mailto]").forEach((el) => {
      el.setAttribute("href", "mailto:hello@kloovi.app");
      if (!el.getAttribute("data-i18n")) {
        el.textContent = "hello@kloovi.app";
      }
    });

    document.querySelectorAll(".lang-switch button").forEach((btn) => {
      const code = btn.getAttribute("data-lang");
      btn.setAttribute("aria-pressed", code === lang ? "true" : "false");
    });

    try {
      localStorage.setItem(STORAGE_KEY, lang);
    } catch (_) {}
  }

  function mountSwitcher() {
    document.querySelectorAll("[data-lang-switch]").forEach((root) => {
      if (root.dataset.ready === "1") return;
      root.dataset.ready = "1";
      root.classList.add("lang-switch");
      root.setAttribute("role", "group");
      root.setAttribute("aria-label", "Language");
      root.innerHTML = "";
      SUPPORTED.forEach((code) => {
        const btn = document.createElement("button");
        btn.type = "button";
        btn.setAttribute("data-lang", code);
        btn.textContent = code.toUpperCase();
        btn.addEventListener("click", () => apply(code));
        root.appendChild(btn);
      });
    });
  }

  function boot() {
    if (!window.KLOOVI_LOCALES) return;
    mountSwitcher();
    apply(detectLang());
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
