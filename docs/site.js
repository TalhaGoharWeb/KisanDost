/* Kisan Dost site — vanilla JS: FAQ accordion, mobile nav, reveal-on-scroll, lightbox.
   No frameworks. Respects prefers-reduced-motion via CSS. */
(function () {
  'use strict';

  /* ---------- FAQ accordion ---------- */
  document.querySelectorAll('.faq-item').forEach(function (item) {
    var q = item.querySelector('.faq-q');
    var a = item.querySelector('.faq-a');
    if (!q || !a) return;
    q.setAttribute('aria-expanded', 'false');
    q.addEventListener('click', function () {
      var isOpen = item.classList.contains('open');
      document.querySelectorAll('.faq-item.open').forEach(function (other) {
        other.classList.remove('open');
        other.querySelector('.faq-a').style.maxHeight = null;
        var oq = other.querySelector('.faq-q');
        if (oq) oq.setAttribute('aria-expanded', 'false');
      });
      if (!isOpen) {
        item.classList.add('open');
        a.style.maxHeight = a.scrollHeight + 'px';
        q.setAttribute('aria-expanded', 'true');
      }
    });
  });

  /* ---------- Mobile nav ---------- */
  var burger = document.querySelector('.burger');
  var links = document.querySelector('.nav-links');
  function closeNav() {
    if (!links) return;
    links.classList.remove('open');
    if (burger) burger.setAttribute('aria-expanded', 'false');
  }
  if (burger && links) {
    burger.setAttribute('aria-expanded', 'false');
    burger.addEventListener('click', function () {
      var open = links.classList.toggle('open');
      burger.setAttribute('aria-expanded', open ? 'true' : 'false');
      if (open) {
        var first = links.querySelector('a');
        if (first) first.focus();
      }
    });
    links.querySelectorAll('a').forEach(function (a) {
      a.addEventListener('click', closeNav);
    });
  }

  /* ---------- Reveal on scroll ---------- */
  var revealEls = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window && revealEls.length) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add('visible'); io.unobserve(e.target); }
      });
    }, { threshold: 0.12 });
    revealEls.forEach(function (el) { io.observe(el); });
  } else {
    revealEls.forEach(function (el) { el.classList.add('visible'); });
  }

  /* ---------- Lightbox ---------- */
  var lb = document.getElementById('lightbox');
  if (lb) {
    var lbImg = lb.querySelector('.lb-img');
    var lbCap = lb.querySelector('.lb-cap');
    var lbClose = lb.querySelector('.lb-close');
    var lbPrev = lb.querySelector('.lb-prev');
    var lbNext = lb.querySelector('.lb-next');
    var shots = Array.prototype.slice.call(document.querySelectorAll('.shot-frame[data-full]'));
    var idx = 0;
    var lastFocus = null;

    function show(i) {
      idx = (i + shots.length) % shots.length;
      var btn = shots[idx];
      var img = btn.querySelector('img');
      lbImg.src = btn.getAttribute('data-full');
      lbImg.alt = img ? (img.getAttribute('alt') || '') : '';
      if (lbCap) lbCap.textContent = btn.getAttribute('data-cap') || lbImg.alt;
    }
    function openLb(i, opener) {
      lastFocus = opener || document.activeElement;
      show(i);
      lb.classList.add('open');
      lb.setAttribute('aria-hidden', 'false');
      document.body.style.overflow = 'hidden';
      if (lbClose) lbClose.focus();
    }
    function closeLb() {
      lb.classList.remove('open');
      lb.setAttribute('aria-hidden', 'true');
      document.body.style.overflow = '';
      lbImg.removeAttribute('src');
      if (lastFocus && lastFocus.focus) lastFocus.focus();
    }
    shots.forEach(function (btn, i) {
      btn.addEventListener('click', function () { openLb(i, btn); });
    });
    if (lbClose) lbClose.addEventListener('click', closeLb);
    if (lbPrev) lbPrev.addEventListener('click', function (e) { e.stopPropagation(); show(idx - 1); });
    if (lbNext) lbNext.addEventListener('click', function (e) { e.stopPropagation(); show(idx + 1); });
    lb.addEventListener('click', function (e) { if (e.target === lb) closeLb(); });
    document.addEventListener('keydown', function (e) {
      if (!lb.classList.contains('open')) {
        if (e.key === 'Escape') closeNav();
        return;
      }
      if (e.key === 'Escape') closeLb();
      else if (e.key === 'ArrowLeft') show(idx - 1);
      else if (e.key === 'ArrowRight') show(idx + 1);
    });
    lb.setAttribute('aria-hidden', 'true');
  } else {
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') closeNav();
    });
  }
})();

/* ============================================================
   2026-10-18: Monetization pages — contact forms + analytics.
   ------------------------------------------------------------
   (a) Contact form (.kd-form): validates, then composes a mailto:
       mailto link to KD_CONFIG.contactEmail with prefilled
       subject/body, opening the user's email app. If no contact
       email is configured, the form is replaced by an honest
       placeholder notice — never a dead form.
   (b) KD.track(eventName): privacy-first analytics hook.
       No-ops unless KD_CONFIG.analyticsEnabled === true.
       Wires [data-track] attributes (download buttons, doc links,
       nav CTAs) as click trackers. No localStorage, no cookies,
       no fingerprinting.
   ============================================================ */
(function () {
  'use strict';

  var cfg = (typeof window !== 'undefined' && window.KD_CONFIG) || {};

  /* ---------- (b) Analytics hook ---------- */
  window.KD = window.KD || {};
  /**
   * Track an event name. No-ops unless analytics is explicitly enabled.
   * A provider hook can be attached as KD.send(eventName) when the
   * owner configures one; until then nothing is recorded.
   */
  window.KD.track = function (eventName) {
    if (!cfg || cfg.analyticsEnabled !== true) return;
    if (typeof window.KD.send === 'function') {
      try { window.KD.send(eventName); } catch (e) { /* never break the page */ }
    }
  };

  /* Wire data-track attributes (runs even when analytics is off —
     KD.track silently no-ops). */
  document.querySelectorAll('[data-track]').forEach(function (el) {
    el.addEventListener('click', function () {
      window.KD.track(el.getAttribute('data-track'));
    });
  });

  /* ---------- (a) Contact / inquiry forms ---------- */
  var REQUIRED_MSG = {
    name: 'براہِ کرم اپنا نام لکھیں۔',
    contact: 'ای میل یا فون نمبر لکھیں تاکہ ہم رابطہ کر سکیں۔',
    message: 'اپنا پیغام لکھیں۔',
    consent: 'آگے بڑھنے کے لیے رابطے کی اجازت ضروری ہے۔'
  };

  function showError(input, field, text) {
    var err = document.getElementById(input.id + '-err');
    if (err) {
      err.textContent = text;
      err.hidden = false;
    }
    input.setAttribute('aria-invalid', 'true');
    field.classList.add('has-error');
  }

  function clearError(input, field) {
    var err = document.getElementById(input.id + '-err');
    if (err) {
      err.textContent = '';
      err.hidden = true;
    }
    input.removeAttribute('aria-invalid');
    field.classList.remove('has-error');
  }

  function checkRequired(input, field, msgKey) {
    var ok = input.type === 'checkbox'
      ? input.checked
      : input.value.trim().length > 0;
    if (!ok) { showError(input, field, REQUIRED_MSG[msgKey]); return false; }
    clearError(input, field);
    return true;
  }

  function labelFor(select, value) {
    var opt = select.querySelector('option[value="' + value + '"]');
    return opt ? opt.textContent : value;
  }

  document.querySelectorAll('form.kd-form').forEach(function (form) {
    var email = (cfg.contactEmail || '').trim();

    /* No configured contact → honest placeholder instead of a dead form. */
    if (!email) {
      var fallback = document.createElement('div');
      fallback.className = 'kd-no-contact notice-box';
      fallback.setAttribute('role', 'status');
      fallback.textContent = 'رابطہ ای میل جلد شائع کی جائے گی۔ اس فارم کے فعال ہونے تک آپ ہم سے براہِ راست رابطہ کر سکتے ہیں۔';
      form.replaceWith(fallback);
      return;
    }

    /* Preset the inquiry-type select if the page declares one. */
    var preset = form.getAttribute('data-preset');
    var typeSel = form.querySelector('#kd-type');
    if (preset && typeSel) typeSel.value = preset;

    var nameIn = form.querySelector('#kd-name');
    var orgIn = form.querySelector('#kd-org');
    var contactIn = form.querySelector('#kd-contact');
    var msgIn = form.querySelector('#kd-message');
    var consentIn = form.querySelector('#kd-consent');
    var notice = form.querySelector('.kd-mailto-note');

    /* Clear errors live as the user types / toggles. */
    form.querySelectorAll('input, select, textarea').forEach(function (input) {
      var field = input.closest('.form-field');
      if (!field) return;
      input.addEventListener('input', function () { clearError(input, field); });
      input.addEventListener('change', function () { clearError(input, field); });
    });

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var ok = true;
      ok = checkRequired(nameIn, nameIn.closest('.form-field'), 'name') && ok;
      ok = checkRequired(contactIn, contactIn.closest('.form-field'), 'contact') && ok;
      ok = checkRequired(msgIn, msgIn.closest('.form-field'), 'message') && ok;
      ok = checkRequired(consentIn, consentIn.closest('.form-field'), 'consent') && ok;
      if (!ok) {
        var firstErr = form.querySelector('.has-error input, .has-error textarea');
        if (firstErr) firstErr.focus();
        return;
      }

      var typeLabel = typeSel ? labelFor(typeSel, typeSel.value) : 'دیگر';
      var subject = 'کسان دوست — ' + typeLabel + ': ' + nameIn.value.trim();
      var lines = [
        'نام: ' + nameIn.value.trim(),
        'تنظیم: ' + (orgIn && orgIn.value.trim() ? orgIn.value.trim() : '—'),
        'ای میل یا فون: ' + contactIn.value.trim(),
        'درخواست کی قسم: ' + typeLabel,
        '',
        'پیغام:',
        msgIn.value.trim()
      ];
      var mailto = 'mailto:' + encodeURIComponent(email) +
        '?subject=' + encodeURIComponent(subject) +
        '&body=' + encodeURIComponent(lines.join('\n'));

      window.location.href = mailto;

      /* Honest notice: the email app opens — nothing is "submitted" yet. */
      if (notice) {
        notice.hidden = false;
        notice.setAttribute('role', 'status');
      }
    });
  });
})();
