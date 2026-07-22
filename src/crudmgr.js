/**
 * Item Manager (CRUD) controller.
 *
 * Owns the add-item modal lifecycle and the mutation-success refresh signal
 * for the CRUD Manager page. It is loaded once from views/layouts/main.pode
 * and scoped to the #crud container so it never touches other pages.
 *
 * Responsibilities:
 *  - Open the modal when the Add Item button is clicked (the htmx request that
 *    loads the form body fires from the button itself).
 *  - Listen for htmx:after:request and close/reset the add form and dispatch
 *    itemChanged ONLY when the request succeeded.
 *  - On a failed POST, keep the modal open, preserve the entered values, and
 *    surface the server message in the role=alert error region.
 *  - Provide dialog accessibility: initial focus, a Tab/Shift+Tab focus loop,
 *    Escape/backdrop close, and focus return to the Add Item button.
 */
(function () {
	'use strict';

	/** @type {HTMLElement | null} */
	let modal = null;
	/** @type {HTMLElement | null} */
	let modalContent = null;
	/** @type {HTMLElement | null} */
	let errorRegion = null;
	/** @type {HTMLElement | null} */
	let lastFocused = null;
	/** @type {(event: KeyboardEvent) => void} */
	let keydownHandler = null;

	/**
	 * Resolve the modal elements from the document. Returns true when every
	 * required element is present so callers can no-op safely on partial DOM.
	 * @returns {boolean}
	 */
	function resolveElements() {
		modal = document.getElementById('itemModal');
		modalContent = document.getElementById('itemModalContent');
		errorRegion = document.getElementById('itemModalError');
		return Boolean(modal && modalContent);
	}

	/**
	 * Collect every focusable control inside the modal for the focus loop.
	 * @returns {HTMLElement[]}
	 */
	function focusableElements() {
		if (!modalContent) return [];
		const selector = 'a[href], button:not([disabled]), textarea:not([disabled]), input:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])';
		return Array.from(modalContent.querySelectorAll(selector)).filter((el) => el.offsetParent !== null || el === document.activeElement);
	}

	function isOpen() {
		return Boolean(modal) && !modal.classList.contains('hidden');
	}

	/**
	 * Trap Tab/Shift+Tab within the modal while it is open.
	 * @param {KeyboardEvent} event
	 */
	function trapFocus(event) {
		if (event.key !== 'Tab' || !isOpen()) return;
		const elements = focusableElements();
		if (elements.length === 0) {
			event.preventDefault();
			return;
		}
		const first = elements[0];
		const last = elements[elements.length - 1];
		if (event.shiftKey) {
			if (document.activeElement === first) {
				event.preventDefault();
				last.focus();
			}
		} else if (document.activeElement === last) {
			event.preventDefault();
			first.focus();
		}
	}

	/**
	 * Open the modal, move focus into it, and wire Escape + focus trapping.
	 */
	function openModal() {
		if (!resolveElements() || isOpen()) return;
		lastFocused = /** @type {HTMLElement | null} */ (document.activeElement);
		modal.classList.remove('hidden');
		modal.classList.add('flex');
		modal.setAttribute('aria-hidden', 'false');
		if (keydownHandler) document.removeEventListener('keydown', keydownHandler);
		keydownHandler = trapFocus;
		document.addEventListener('keydown', keydownHandler);
		// Move focus to the first focusable control (the item name field once the
		// form body has loaded, otherwise the close button).
		requestAnimationFrame(() => {
			const elements = focusableElements();
			const itemField = modalContent.querySelector('input[name="item"]');
			if (itemField instanceof HTMLElement) {
				itemField.focus();
			} else if (elements.length > 0) {
				elements[0].focus();
			}
		});
	}

	/**
	 * Close the modal, reset the add form, clear the error region, and return
	 * focus to the button that opened it.
	 */
	function closeModal() {
		if (!resolveElements()) return;
		const form = modalContent.querySelector('form');
		if (form instanceof HTMLFormElement) {
			form.reset();
		}
		clearError();
		modal.classList.add('hidden');
		modal.classList.remove('flex');
		modal.setAttribute('aria-hidden', 'true');
		if (keydownHandler) {
			document.removeEventListener('keydown', keydownHandler);
			keydownHandler = null;
		}
		if (lastFocused instanceof HTMLElement) {
			lastFocused.focus();
			lastFocused = null;
		}
	}

	/**
	 * Render a failed-mutation message into the role=alert region without
	 * clearing the form values the user entered.
	 * @param {string} message
	 */
	function showError(message) {
		if (!resolveElements() || !errorRegion) return;
		errorRegion.textContent = message;
		errorRegion.classList.remove('hidden');
	}

	/**
	 * Hide the error region (called on close/reset).
	 */
	function clearError() {
		if (!resolveElements() || !errorRegion) return;
		errorRegion.textContent = '';
		errorRegion.classList.add('hidden');
	}

	/**
	 * Dispatch the itemChanged event on <body> so the #crud container re-requests
	 * the collection and the table refreshes.
	 */
	function dispatchItemChanged() {
		document.body.dispatchEvent(new CustomEvent('itemChanged'));
	}

	/**
	 * Determine whether an htmx request context represents a successful CRUD
	 * mutation (POST/PUT/DELETE against /api/crud with a 2xx response).
	 * @param {object} ctx The htmx 4 request context (event.detail.ctx).
	 * @returns {boolean}
	 */
	function isSuccessfulMutation(ctx) {
		const method = String(ctx?.request?.method || '').toUpperCase();
		const action = String(ctx?.request?.action || '');
		const status = Number(ctx?.response?.status || 0);
		if (!['POST', 'PUT', 'DELETE'].includes(method)) return false;
		if (!action.includes('/api/crud')) return false;
		return status >= 200 && status < 300;
	}

	/**
	 * Handle htmx:after:request bubbled to document.body. Only successful CRUD
	 * mutations close the modal and refresh the list; failures keep the modal
	 * open and surface the server message.
	 * @param {CustomEvent} event
	 */
	function handleAfterRequest(event) {
		const ctx = event.detail?.ctx || {};
		const method = String(ctx?.request?.method || '').toUpperCase();

		// Only react to CRUD mutation requests against /api/crud.
		if (!isCrudMutation(ctx)) return;

		const success = isSuccessfulMutation(ctx);

		if (method === 'POST') {
			// POST originates from the add-item form inside the modal.
			if (success) {
				closeModal();
				dispatchItemChanged();
			} else {
				// Keep the modal open and preserve values; surface the message.
				showError(extractMessage(ctx));
			}
			return;
		}

		// PUT / DELETE originate from inline table controls; refresh only on success.
		if (success) {
			dispatchItemChanged();
		}
	}

	/**
	 * Determine whether an htmx request context targets a CRUD mutation
	 * (POST/PUT/DELETE against /api/crud), regardless of success.
	 * @param {object} ctx
	 * @returns {boolean}
	 */
	function isCrudMutation(ctx) {
		const method = String(ctx?.request?.method || '').toUpperCase();
		const action = String(ctx?.request?.action || '');
		if (!['POST', 'PUT', 'DELETE'].includes(method)) return false;
		return action.includes('/api/crud');
	}

	/**
	 * Extract the { message } text from an htmx response context, tolerating
	 * non-JSON or empty bodies.
	 * @param {object} ctx
	 * @returns {string}
	 */
	function extractMessage(ctx) {
		const raw = ctx?.text;
		if (!raw) return 'The request failed. Please try again.';
		try {
			const parsed = JSON.parse(raw);
			if (parsed && typeof parsed.message === 'string') return parsed.message;
		} catch {
			// Not JSON; fall through to the generic message.
		}
		return 'The request failed. Please try again.';
	}

	/**
	 * Wire the controller to the #crud container and document-level handlers.
	 * Safe to call multiple times: it locates elements fresh each time.
	 */
	function init() {
		const crud = document.getElementById('crud');
		if (!crud) return;
		if (crud.dataset.crudController === 'bound') return;
		crud.dataset.crudController = 'bound';

		// Mutation lifecycle: the after:request event bubbles from the add-item
		// form (inside #itemModal, a sibling of #crud) and the inline update/delete
		// controls (inside #crud). Listening on document.body catches both while
		// the init guard above scopes the controller to the CRUD page.
		document.body.addEventListener('htmx:after:request', handleAfterRequest);

		// Add Item button: open the modal. The htmx GET that loads the form body
		// is declared on the button itself; openModal runs once that settles.
		const addItemBtn = document.getElementById('addItemBtn');
		if (addItemBtn) {
			addItemBtn.addEventListener('click', () => {
				// Open immediately so the backdrop is visible while the form loads.
				openModal();
			});
		}

		// When the form body is swapped into #itemModalContent, ensure the modal
		// is open and focus lands inside it.
		document.body.addEventListener('htmx:after:settle', (event) => {
			const target = event.target;
			if (target instanceof HTMLElement && target.id === 'itemModalContent') {
				openModal();
			}
		});

		// Delegated clicks inside the modal: close button, Cancel button, and
		// backdrop click-to-close.
		resolveElements();
		if (modal) {
			modal.addEventListener('click', (event) => {
				const target = event.target;
				if (!(target instanceof HTMLElement)) return;
				// Backdrop click: the click landed on the modal overlay itself, not
				// its content child.
				if (target === modal) {
					closeModal();
					return;
				}
				// Close control or Cancel button carry data-close-modal.
				if (target.closest('[data-close-modal]')) {
					closeModal();
				}
			});
		}

		// Escape closes the modal (also handled by trapFocus for Tab).
		document.addEventListener('keydown', (event) => {
			if (event.key === 'Escape' && isOpen()) {
				closeModal();
			}
		});
	}

	// Expose the modal API on window so inline hx-on handlers (if any remain)
	// and tests can drive it, while the lifecycle is owned here.
	window.PodexCrud = {
		openModal,
		closeModal,
		showError,
		dispatchItemChanged,
		isOpen,
	};

	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', init);
	} else {
		init();
	}
})();
