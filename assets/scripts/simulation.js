///////////////////////////////////////////////////////////////////////////////
//
// Simulation.js
//
///////////////////////////////////////////////////////////////////////////////


var refreshInterval = 500;

//---

function initSimulation() {
	if ($('#page-simulation').length <= 0) return;

	initDatabaseButtons();
	initDatabaseQuerySelect();
	initStartSimulatorButton();
}

//---

function initDatabaseButtons() {
	// Decide which buttons to show initially
	$.ajax({
		url: '/is_cluster_test_database_imported',
		type: 'GET'
	}).done(function(data) {
		var imported = data.result;

		if (imported) {
			$('#delete-cluster-test-database').show();
			$('#database-more-operations').show();
		} else {
			$('#import-cluster-test-database').show();
		}
	});

	// When the import button is clicked...
	$('#import-cluster-test-database').click(function() {
		if (getClusterStatus() != 'online') {
			alert('Cluster ist nicht online!');
			return;
		}

		var ladda = Ladda.create(this);
		ladda.start();

		$.ajax({
			url: '/import_cluster_test_database',
			type: 'GET'
		}).done(function(data) {
			var importSuccess = data.result;
			ladda.stop();

			var message = '';

			if (importSuccess) {
				message  = 'TPCW-Datenbank erfolgreich importiert.';
				$('#import-cluster-test-database').fadeOut();
				$('#database-more-operations').slideDown();
				$('#delete-cluster-test-database').fadeIn();
			} else {
				message  = 'Datenbank konnte leider (noch) nicht ';
				message += 'importiert werden. ';
				message += 'Mehr Hinweise sind in den Log-Dateien zu finden.';
			}

			alert(message);
		});
	});

	// Whent the delete button is clicked...
	$('#delete-cluster-test-database').click(function() {
		if (getClusterStatus() != 'online') {
			alert('Cluster ist nicht online!');
			return;
		}

		var ladda = Ladda.create(this);
		ladda.start();

		$.ajax({
			url: '/delete_cluster_test_database',
			type: 'GET'
		}).done(function(data) {
			var result = data.result;
			ladda.stop();

			var message = '';

			if (result == 'success') {
				message  = 'TPCW-Datenbank erfolgreich gelöscht.';
				$('#database-more-operations').slideUp();
				$('#delete-cluster-test-database').fadeOut();
				$('#import-cluster-test-database').fadeIn();
			} else {
				message  = 'Datenbank konnte leider nicht gelöscht werden. ';
				message += 'Mehr Hinweise sind in den Log-Dateien zu finden.';
			}

			alert(message);
		});
	});

	// When the data record button is clicked...
	$('#get-data-record-count').click(function() {
		if (getClusterStatus() != 'online') {
			alert('Cluster ist nicht online!');
			return;
		}

		$.ajax({
			url: '/data_record_count',
			type: 'GET'
		}).done(function(data) {
			var result = data.result,
				msg = '';

			for (var key in result) {
				msg += key + ': ' + result[key] + '\n';
			}

			alert(msg);
		});
	});

	// When the insert button is clicked...
	$('#insert-into-database-until-scaling').click(function() {
		if (getClusterStatus() != 'online') {
			alert('Cluster ist nicht online!');
			return;
		}

		var ladda = Ladda.create(this);
		ladda.start();

		$.ajax({
			url: '/insert_into_database_until_scaling',
			type: 'GET'
		}).done(function(data) {
			var result = data.result;
			ladda.stop();

			if (result) {
				alert('Weitere Daten werden eingespielt.')
			} else {
				alert('Die Datenbank konnte leider nicht gefüllt werden. Mehr Informationen sind in den Log-Dateien enthalten.')
			}
		});	
	});

	// When the remove button is clicked...
	$('#remove-from-database-until-scaling').click(function() {
		if (getClusterStatus() != 'online') {
			alert('Cluster ist nicht online!');
			return;
		}

		var ladda = Ladda.create(this);
		ladda.start();

		$.ajax({
			url: '/remove_from_database_until_scaling',
			type: 'GET'
		}).done(function(data) {
			var result = data.result;
			ladda.stop();

			if (result) {
				alert('Daten werden gelöscht.')
			} else {
				alert('Daten konnten leider nicht gelöscht werden. Mehr Informationen sind in den Log-Dateien enthalten.')
			}
		});	
	});
}

//---

function initDatabaseQuerySelect() {
	$('#selected-query').change(function() {
		if ($(this).val() == '---- Eigene ----') {
			$('#custom-query').slideDown();
		} else {
			$('#custom-query').slideUp();
		}
	});
}

//---

function initStartSimulatorButton() {
	$('#start-simulator').click(function() {
		if (getClusterStatus() != 'online') {
			alert('Cluster ist nicht online!');
			return;
		}

		var ladda = Ladda.create(this),
			statusValue = 0;

		ladda.start();
		
		$('#simulator-result-container').slideUp();
		$('#simulator-progress').fadeIn();

		// Get configured simulation options
		var query = $('#selected-query').val();

		if (query == '---- Eigene ----') {
			query = $('#simulation-query').val();
		}

		var queryCount = $('#query-count').val(),
			threadCount = $('#thread-count').val();

		// Make the server request
		$.ajax({
			url: '/start_simulator',
			type: 'GET',
			data: {
				query: 			query,
				queryCount: 	queryCount,
				threadCount: 	threadCount
			}
		}).done(function(data) {
			var result = data.result,
				benchmarkResult = result.benchmark_result;

			statusValue = 100;
			ladda.stop();
			$('#simulator-progress').fadeOut();
			
			if (benchmarkResult != false) {
				$('#benchmark-result span').html(benchmarkResult);
				$('#simulator-result-container').slideDown();
			} else {
				alert('Die Simulation konnte leider nicht durchgeführt werden. Mehr Informationen sind in den Log-Dateien enthalten.')
			}
		});

		var updateProgressBar = function() {
			var loop = setInterval(function() {
				if (statusValue != 100) {
					$.ajax({
						url: '/simulator_status',
						type: 'GET',
						data: {
							queryCount: 	queryCount,
							threadCount: 	threadCount
						}
					}).done(function(data) {
						statusValue = data.result;
						var progressBar = $('#simulator-progress .progress-bar');
						progressBar.attr('aria-valuenow', statusValue);
						progressBar.width(statusValue + '%');
						progressBar.html(statusValue + '%');
					});			
				} else {
					clearInterval(loop);
				}
			}, refreshInterval);
		};

		updateProgressBar();
	});	
}