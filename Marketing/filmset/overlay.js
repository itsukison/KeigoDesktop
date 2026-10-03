/* Recreated filming overlay. Fixed script output only; no AI, accounts, or native
 * capture. The web page owns its composer and can replay every take offline. */
window.FilmsetOverlay = {
  mount({ box, getScenario, setText, tokens = [], enabled = true }) {
    if (!enabled || tokens.includes('overlay=off')) return;
    const scaleToken = tokens.map(t => /^buttonscale=([\d.]+)$/.exec(t)).find(Boolean);
    if (scaleToken && Number.isFinite(Number(scaleToken[1]))) {
      document.documentElement.style.setProperty('--kb-scale', Math.min(2, Math.max(1, Number(scaleToken[1]))));
    }
    const ja = document.documentElement.lang === 'ja';
    const tr = (j, e) => ja ? j : e;
    const root = document.createElement('div');
    root.id = 'kb-overlay';
    root.setAttribute('aria-label', tr('文章作成バー', 'Writing bar'));
    document.body.append(root);
    let state = 'pill', source = '', mode = 'keigo', guidance = '', captured = null;
    let pages = [], pageIndex = 0, vote = '', generationTimer, collapseTimer, refineTimer, toastTimer;
    let refining = false, internalCopy = false, notice = '', frame = 0;
    const reduced = matchMedia('(prefers-reduced-motion: reduce)');
    const esc = value => {
      const node = document.createElement('span');
      node.textContent = value;
      return node.innerHTML.replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    };
    const icon = name => `<i class="kb-icon" aria-hidden="true" style="--icon:url('assets/overlay/${name}.png')"></i>`;
    const mark = animation => `<span class="kb-mascot" data-animation="${animation}" aria-hidden="true">${source && state === 'pill' ? '<i class="kb-dot"></i>' : ''}</span>`;
    const button = (action, label, content, cls = '', extra = '') =>
      `<button type="button" data-action="${action}" class="${cls}" aria-label="${esc(label)}" title="${esc(label)}" ${extra}>${content}</button>`;
    const close = (action = 'dismiss', cls = 'kb-close') => button(action, tr('閉じる', 'Close'), icon('xmark'), cls);
    const footerIcon = (name, label, extra = '') => button(name, label, icon(name), 'kb-footer-icon', extra);
    const currentOutput = () => pages[pageIndex] || getScenario().corporate;

    function render() {
      clearTimeout(refineTimer);
      root.dataset.state = state;
      let html;
      if (state === 'pill') {
        html = `<div class="kb-rest kb-glass">${mark('idle')}</div>`;
      } else if (state === 'hover') {
        const titles = ja ? ['敬語', 'メール', '英訳', '自然に'] : ['Grammar', 'Email', 'Simplify', 'Formal'];
        html = `<div class="kb-actions kb-glass">${mark('engaged')}<i class="kb-divider"></i>
          <div class="kb-prompts">${titles.map(title => button('rewrite', title, esc(title), 'kb-prompt')).join('')}</div>
          <i class="kb-divider"></i>${source ? `<span class="kb-reply-action">
            ${button('reply', tr('返信', 'Reply'), tr('返信', 'Reply'), 'kb-reply')}
            ${close('clear-source', 'kb-dismiss-source')}</span>` : ''}
          ${button('custom', tr('指示を書く', 'Write instructions'), icon('pencil'), 'kb-pencil')}</div>`;
      } else if (state === 'input') {
        const placeholder = mode === 'reply' ? tr('返信の指示（空欄でおまかせ）', 'Reply instructions (optional)')
          : captured?.text ? tr('どう書き換えますか？', 'How should this be rewritten?') : tr('何を書きますか？', 'What should I write?');
        html = `<div class="kb-composer kb-glass ${mode === 'reply' ? 'kb-with-source' : ''}">
          ${mode === 'reply' ? `<div class="kb-source">${icon('arrowshape.turn.up.left')}
            <span class="kb-source-text" title="${esc(source)}">${esc(source)}</span>${close('clear-source', 'kb-dismiss-source')}</div>
            <div class="kb-source-rule"></div>` : ''}
          <div class="kb-input-row">${mark('engaged')}
            <textarea class="kb-input" rows="1" aria-label="${esc(placeholder)}" placeholder="${esc(placeholder)}" spellcheck="false">${esc(guidance)}</textarea>
            ${button('submit', tr('生成', 'Generate'), icon('arrow.up.circle.fill'), 'kb-submit', mode !== 'reply' && !guidance.trim() ? 'disabled' : '')}
          </div></div>`;
      } else if (state === 'generating') {
        html = `<div class="kb-generating kb-glass">${mark('thinking')}
          <span class="kb-generating-label">${mode === 'reply' ? tr('返信を生成中', 'Replying…') : tr('生成中', 'Writing…')}</span>
          ${close('cancel', 'kb-cancel')}</div>`;
      } else {
        html = `<div class="kb-result kb-glass" role="dialog" aria-label="${tr('生成結果', 'Result')}">
          <div class="kb-result-header"><div class="kb-pager">
            ${button('previous', tr('前の結果', 'Previous result'), icon('chevron.left'), '', pageIndex === 0 ? 'disabled' : '')}
            <span>${pageIndex + 1} / ${pages.length}</span>
            ${button('next', tr('次の結果', 'Next result'), icon('chevron.right'), '', pageIndex === pages.length - 1 ? 'disabled' : '')}
          </div>${close()}</div>
          <div class="kb-result-body">${esc(currentOutput())}</div>
          <div class="kb-notice-slot" aria-hidden="true"></div>
          <div class="kb-footer">${refining ? `<div class="kb-refinement">
            <input aria-label="${tr('指示を追加', 'Add an instruction')}" placeholder="${tr('指示を追加（空欄でそのまま再生成）', 'Add an instruction (leave blank to regenerate)')}">
            ${button('regenerate', tr('送信', 'Send'), icon('arrow.up'))}</div>`
            : `${footerIcon('arrow.clockwise', tr('再生成', 'Regenerate'))}
              ${footerIcon('doc.on.doc', tr('コピー', 'Copy'))}
              ${footerIcon('hand.thumbsup', tr('良い結果', 'Good result'), `aria-pressed="${vote === 'up'}"`)}
              ${footerIcon('hand.thumbsdown', tr('良くない結果', 'Poor result'), `aria-pressed="${vote === 'down'}"`)}
              <span class="kb-footer-space"></span>${button('insert', tr('挿入', 'Insert'), `${tr('挿入', 'Insert')}${icon('return')}`, 'kb-insert')}`}
          </div></div>`;
      }
      root.innerHTML = html + (notice ? `<div class="kb-toast kb-glass" role="status">${esc(notice)}</div>` : '');
      if (state === 'input') {
        const input = root.querySelector('.kb-input');
        resizeInput(input);
        input.focus({ preventScroll: true });
        input.setSelectionRange(input.value.length, input.value.length);
      }
    }

    function resizeInput(input) {
      input.style.height = '18px';
      input.style.height = `${Math.min(54, Math.max(18, input.scrollHeight))}px`;
    }
    function change(next) {
      clearTimeout(collapseTimer);
      collapseTimer = null;
      clearTimeout(refineTimer);
      state = next;
      render();
    }
    function notify(text) {
      notice = text;
      clearTimeout(toastTimer);
      render();
      toastTimer = setTimeout(() => { notice = ''; render(); }, 8000);
    }
    function capture() {
      captured = { value: box.value, start: box.selectionStart, end: box.selectionEnd };
      captured.text = captured.start === captured.end ? captured.value : captured.value.slice(captured.start, captured.end);
    }
    function openInput(reply = false, preload = false) {
      capture();
      mode = reply ? 'reply' : 'custom';
      guidance = preload ? getScenario().guidance || getScenario().genz : '';
      change('input');
    }
    function generate(append = false) {
      if (state === 'generating') return;
      notice = '';
      refining = false;
      if (!append) { pages = []; pageIndex = 0; vote = ''; }
      change('generating');
      const token = tokens.map(t => /^delay=(\d+)$/.exec(t)).find(Boolean);
      const delay = token ? Math.min(10000, Number(token[1])) : 1100;
      clearTimeout(generationTimer);
      generationTimer = setTimeout(() => {
        pages.push(getScenario().corporate);
        pageIndex = pages.length - 1;
        change('result');
      }, delay);
    }
    function dismiss() {
      clearTimeout(generationTimer);
      guidance = '';
      refining = false;
      change('pill');
      box.focus({ preventScroll: true });
    }
    function clearSource() { source = ''; dismiss(); }
    function arm(text) {
      source = text;
      if (state === 'pill' || state === 'hover') render();
    }
    async function copy(text) {
      try { await navigator.clipboard.writeText(text); }
      catch {
        const temp = document.createElement('textarea');
        temp.value = text; temp.style.cssText = 'position:fixed;left:-9999px';
        document.body.append(temp); temp.select(); internalCopy = true;
        try { document.execCommand('copy'); } finally { internalCopy = false; temp.remove(); }
      }
    }
    const actions = {
      rewrite() {
        capture();
        if (!captured.text.trim()) { notify(tr('書き換える文章を入力してください。クリックで閉じます。', 'Type something to rewrite. Click to dismiss.')); return; }
        mode = 'keigo'; generate();
      },
      custom: () => openInput(), reply: () => openInput(true),
      submit() { if (mode === 'reply' || guidance.trim()) generate(); },
      cancel: dismiss, dismiss, 'clear-source': clearSource,
      insert() {
        const text = currentOutput();
        const selected = mode !== 'reply' && captured && captured.start !== captured.end;
        setText(selected ? captured.value.slice(0, captured.start) + text + captured.value.slice(captured.end) : text);
        source = ''; dismiss();
      },
      'doc.on.doc': () => copy(currentOutput()),
      'hand.thumbsup': () => { vote = vote === 'up' ? '' : 'up'; render(); },
      'hand.thumbsdown': () => { vote = vote === 'down' ? '' : 'down'; render(); },
      'arrow.clockwise': () => generate(true), regenerate: () => generate(true),
      previous: () => { if (pageIndex > 0) { pageIndex--; refining = false; render(); } },
      next: () => { if (pageIndex < pages.length - 1) { pageIndex++; refining = false; render(); } },
    };
    root.addEventListener('click', event => {
      if (event.target.closest('.kb-toast')) { notice = ''; render(); return; }
      const action = event.target.closest('button[data-action]');
      if (action && !action.disabled) actions[action.dataset.action]?.();
    });
    root.addEventListener('mouseenter', () => {
      clearTimeout(collapseTimer);
      collapseTimer = null;
      if (state === 'pill') change('hover');
    });
    function scheduleCollapse() {
      if (state !== 'hover' || collapseTimer) return;
      collapseTimer = setTimeout(() => {
        collapseTimer = null;
        if (state === 'hover') change('pill');
      }, 300);
    }
    root.addEventListener('mouseleave', scheduleCollapse);
    // Replacing the collapsed child during mouseenter can invalidate Chromium's
    // hover chain without a subsequent mouseleave. Track the stable root's bounds.
    document.addEventListener('pointermove', event => {
      if (state !== 'hover') return;
      const r = root.getBoundingClientRect();
      if (event.clientX >= r.left && event.clientX <= r.right && event.clientY >= r.top && event.clientY <= r.bottom) {
        clearTimeout(collapseTimer); collapseTimer = null;
      } else scheduleCollapse();
    });
    root.addEventListener('mouseover', event => {
      if (state === 'result' && !refining && event.target.closest('[data-action="arrow.clockwise"]')) {
        clearTimeout(refineTimer);
        refineTimer = setTimeout(() => { if (state === 'result') { refining = true; render(); } }, 400);
      }
    });
    root.addEventListener('mouseout', event => {
      if (event.target.closest('[data-action="arrow.clockwise"]')) clearTimeout(refineTimer);
      if (refining && !event.relatedTarget?.closest('.kb-refinement') && !root.querySelector('.kb-refinement')?.contains(document.activeElement)) {
        clearTimeout(refineTimer);
        refineTimer = setTimeout(() => { if (state === 'result') { refining = false; render(); } }, 300);
      }
    });
    root.addEventListener('input', event => {
      if (!event.target.matches('.kb-input')) return;
      guidance = event.target.value;
      resizeInput(event.target);
      root.querySelector('[data-action="submit"]').disabled = mode !== 'reply' && !guidance.trim();
    });
    document.addEventListener('pointerdown', event => {
      if (state === 'input' && !root.contains(event.target)) dismiss();
    });
    document.addEventListener('copy', () => {
      if (internalCopy) return;
      const selection = getSelection();
      if (!selection || selection.isCollapsed || !selection.rangeCount) return;
      const parent = selection.getRangeAt(0).commonAncestorContainer;
      const element = parent.nodeType === Node.ELEMENT_NODE ? parent : parent.parentElement;
      if (element?.closest('.msgs .msg[data-received]')) arm(selection.toString().trim());
    });
    document.addEventListener('filmset:scenario', () => {
      clearTimeout(generationTimer); clearTimeout(toastTimer); notice = ''; source = '';
      pages = []; captured = null; dismiss();
    });
    document.addEventListener('keydown', event => {
      if (event.isComposing || event.keyCode === 229) return;
      if (event.key === 'Escape' && state !== 'pill') {
        event.preventDefault();
        if (refining) { refining = false; render(); } else dismiss();
      } else if (event.key === 'Enter' && (state === 'input' || state === 'result')) {
        event.preventDefault();
        if (state === 'input') actions.submit();
        else if (refining) generate(true);
        else actions.insert();
      } else if (event.altKey && !event.metaKey && !event.ctrlKey) {
        if (event.code === 'KeyR') { event.preventDefault(); arm(getScenario().trigger || getScenario().thread.filter(m => !m.me).at(-1).text); }
        if (event.code === 'KeyI') {
          event.preventDefault(); dismiss();
          if (getScenario().mode === 'reply') { arm(getScenario().trigger); setText(''); openInput(true, true); }
          else setText(getScenario().genz);
        }
        if (event.code === 'KeyC') { source = ''; dismiss(); }
      }
    }, true);
    // Native atlases are 4 x 4 frames at 4 fps. Keep that cadence and actual pixels.
    setInterval(() => {
      frame = reduced.matches ? 0 : (frame + 1) % 16;
      for (const sprite of root.querySelectorAll('.kb-mascot'))
        sprite.style.backgroundPosition = `${-(frame % 4) * 16}px ${-Math.floor(frame / 4) * 16}px`;
    }, 250);
    render();
    if (tokens.includes('expanded')) change('hover');
    if (tokens.includes('intent')) {
      arm(getScenario().trigger || getScenario().thread.filter(m => !m.me).at(-1).text);
      openInput(true, true);
    }
    if (tokens.includes('result')) { capture(); mode = getScenario().mode || 'keigo'; pages = [getScenario().corporate]; change('result'); }
  }
};
