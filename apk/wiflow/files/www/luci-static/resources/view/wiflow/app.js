'use strict';
'require view';

// Wiflow Setup is its own page (/wiflow/, the CR6609 Setup design). It runs on
// this LuCI session: hand the session id over and open it.
return view.extend({
	render: function() {
		var page = 'status', stored = false;
		try {
			page = sessionStorage.getItem('wf-page') || 'status';
			sessionStorage.removeItem('wf-page');
			sessionStorage.setItem('wf-sid', L.env.sessionid);
			stored = sessionStorage.getItem('wf-sid') == L.env.sessionid;
		} catch (e) {}
		if (!/^(status|internet|guest|system)$/.test(page))
			page = 'status';
		// no sessionStorage (private mode): the id rides in the hash, the page drops it at once
		window.location.replace('/wiflow/#' + page + (stored ? '' : '/' + L.env.sessionid));
		return E('p', { 'style': 'padding:24px' }, 'Đang mở Wiflow Setup…');
	},
	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
