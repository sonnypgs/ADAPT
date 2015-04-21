///////////////////////////////////////////////////////////////////////////////
//
// Logging.js
//
///////////////////////////////////////////////////////////////////////////////


function initLogging() {
	if ($('#page-logging').length <= 0) return;

	initLogFiles();
}

//---

function initLogFiles() {
	loadLogFile();

	$('#page-logging select').change(function() {
		loadLogFile();
	});

	$('#page-logging #refresh').click(function() {
		loadLogFile();
	});	
}

//---

function loadLogFile() {
	var logFileName = $('#page-logging select option:selected').text(); 
	$.ajax({
		url: '/log_file',
		type: 'GET',
		data: {
			logFileName: logFileName
		}
	}).done(function(data) {
		var result = data.result;
		$('#page-logging textarea').html(result);
	});		
}