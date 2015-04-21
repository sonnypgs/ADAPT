///////////////////////////////////////////////////////////////////////////////
//
// CloudStack.js
//
///////////////////////////////////////////////////////////////////////////////


function initCloudStack() {
	if ($('#page-cloudstack').length <= 0) return;

	initVMButton();
}

//---

function initVMButton() {
	$('.x-vm').click(function() {
		var operation = $(this).data('operation');
		xVM(this, operation);
	});	
}

//---

function xVM(vmRow, operation) {
	var rowContainer = $(vmRow).parent().parent(),
		vmIdContainer = rowContainer.find('.vm-id'),
		vmId = $(vmIdContainer[0]).html();

	$.ajax({
		url: '/' + operation,
		type: 'GET',
		data: {
			vmId: vmId
		}
	}).done(function(data) {
		var jobId = data.result,
			error = data.error;
		
		if (typeof jobId != 'undefined') {
			$('#ajax-loader-container').fadeIn(500);

			var loop = setInterval(function() {
				$.ajax({
					url: '/async_job_result',
					type: 'GET',
					data: {
						jobId: jobId
					}
				}).done(function(data) {
					var result = data.result;

					if (result.jobstatus == 1) {
						clearInterval(loop);
						$('#ajax-loader-container').fadeOut(500);
						var state = result.jobresult.virtualmachine.state,
							currentCSSClass = rowContainer.find('.vm-state').attr('class').split(/\s+/)[1];

						rowContainer.find('.vm-state').switchClass(currentCSSClass, 'vm-state-'+state.toLowerCase(), 500);

						rowContainer.find('.vm-state').html(state);
					}
				});
			}, 2000);			
		} else {
			var message = 'Fehler: ' + 'Der momentate Status der VM ist "';
				message += error + '"';

			alert(message);
		}
	});
}