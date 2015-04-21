//////////////////////////////////////////////
//
// Shared
//
//////////////////////////////////////////////


function initShared() {
	extendArray();
	initPageEffects();
	initGoBackButton();
	initResetCluster();
}

//---

function initPageEffects() {
	if ($('.main').length > 0) {
		$('.main').delay(400).slideDown(800);
	}

	if ($('.navbar-brand').length > 0) {
		$('.navbar-brand').delay(400+800).addClass('ready');
	}
}

//---

function initGoBackButton() {
	if ($('#go-back').length > 0) {
		$('#go-back').click(function() {
			window.history.back();
		});
	}
}

//---

function initResetCluster() {
	if ($('#reset-cluster').length <= 0) return;
	
	$('#reset-cluster').click(function() {
		var reset = confirm('Cluster wirklich zurücksetzen?');
		if (reset) {
			$.ajax({
				type: 'GET',
				url: '/reset_cluster'
			}).done(function(data) {
				var result = data.result,
					message = '';

				if (result) {
					message = 'Cluster wird zurückgesetzt.'
				} else {
					message = 'Cluster konnte nicht zurückgesetzt werden.'
				}

				alert(message);
			});
		}
	});	
}

//---

function getClusterStatus() {
	status = 'offline';

	$.ajax({
		url: '/cluster_status',
		type: 'GET',
		async: false
	}).done(function(data) {
		status = data.result;
	});

	return status;
}

//---

function extendArray() {
	Array.prototype.unique = function() {
		var n = {}, r=[];
		for (var i = 0; i < this.length; i++) {
			if (!n[this[i]]) {
				n[this[i]] = true; 
				r.push(this[i]); 
			}
		}
		return r;
	}
}