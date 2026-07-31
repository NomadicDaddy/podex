import type { HtmxEvent, HtmxRequestCtx } from 'htmx.org';

let modal: HTMLElement | null = null;
let modalContent: HTMLElement | null = null;
let lastFocused: HTMLElement | null = null;
let keydownHandler: ((event: KeyboardEvent) => void) | null = null;

function resolveElements(): boolean {
	modal = document.getElementById('itemModal');
	modalContent = document.getElementById('itemModalContent');
	return Boolean(modal && modalContent);
}

function focusableElements(): HTMLElement[] {
	if (!modalContent) return [];
	const selector =
		'a[href], button:not([disabled]), textarea:not([disabled]), input:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])';
	return Array.from(modalContent.querySelectorAll<HTMLElement>(selector)).filter(
		(element) => element.offsetParent !== null || element === document.activeElement,
	);
}

function isOpen(): boolean {
	return modal?.getAttribute('aria-hidden') === 'false';
}

function trapFocus(event: KeyboardEvent): void {
	if (event.key !== 'Tab' || !isOpen()) return;
	const elements = focusableElements();
	const first = elements[0];
	const last = elements.at(-1);
	if (!first || !last) {
		event.preventDefault();
		return;
	}
	if (event.shiftKey && document.activeElement === first) {
		event.preventDefault();
		last.focus();
	} else if (!event.shiftKey && document.activeElement === last) {
		event.preventDefault();
		first.focus();
	}
}

function openModal(): void {
	if (!resolveElements() || !modal || !modalContent || isOpen()) return;
	lastFocused = document.activeElement instanceof HTMLElement ? document.activeElement : null;
	modal.setAttribute('aria-hidden', 'false');
	if (keydownHandler) document.removeEventListener('keydown', keydownHandler);
	keydownHandler = trapFocus;
	document.addEventListener('keydown', keydownHandler);
	requestAnimationFrame(() => {
		const elements = focusableElements();
		const itemField = modalContent?.querySelector<HTMLInputElement>('input[name="item"]');
		(itemField ?? elements[0])?.focus();
	});
}

function closeModal(): void {
	if (!resolveElements() || !modal || !modalContent) return;
	modalContent.querySelector<HTMLFormElement>('form')?.reset();
	document.getElementById('itemModalError')?.replaceChildren();
	modal.setAttribute('aria-hidden', 'true');
	if (keydownHandler) {
		document.removeEventListener('keydown', keydownHandler);
		keydownHandler = null;
	}
	if (lastFocused) {
		lastFocused.focus();
		lastFocused = null;
	}
}

function isSuccessfulCreate(ctx: HtmxRequestCtx): boolean {
	const status = ctx.response?.status ?? 0;
	return (
		ctx.request.method.toUpperCase() === 'POST' &&
		ctx.request.action.includes('/api/crud') &&
		status >= 200 &&
		status < 300
	);
}

function handleAfterRequest(event: Event): void {
	const { ctx } = (event as HtmxEvent<'htmx:after:request'>).detail;
	if (isSuccessfulCreate(ctx)) closeModal();
}

function setBusy(busy: boolean): void {
	const region = document.getElementById('crud-list');
	if (!region) return;
	if (busy) {
		region.setAttribute('aria-busy', 'true');
	} else {
		region.setAttribute('aria-busy', 'false');
	}
}

function init(): void {
	const crud = document.getElementById('crud');
	if (!crud || crud.dataset.crudController === 'bound') return;
	crud.dataset.crudController = 'bound';

	document.body.addEventListener('htmx:after:request', handleAfterRequest);
	document.body.addEventListener('htmx:before:request', () => setBusy(true));
	document.body.addEventListener('htmx:after:request', () => setBusy(false));

	document.body.addEventListener('htmx:after:settle', (event) => {
		const target = event.target;
		if (target instanceof HTMLElement && target.id === 'itemModalContent') openModal();
	});

	resolveElements();
	modal?.addEventListener('click', (event) => {
		const target = event.target;
		if (!(target instanceof Element)) return;
		if (target === modal || target.closest('[data-close-modal]')) closeModal();
	});
	document.addEventListener('keydown', (event) => {
		if (event.key === 'Escape' && isOpen()) closeModal();
	});
}

if (document.readyState === 'loading') {
	document.addEventListener('DOMContentLoaded', init);
} else {
	init();
}
