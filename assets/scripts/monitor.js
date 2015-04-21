///////////////////////////////////////////////////////////////////////////////
//
// Monitor.js
//
///////////////////////////////////////////////////////////////////////////////


var latencyGraph,
	capacityGraph,
	refreshInterval = 500;

//---

function initMonitor() {
	if ($('#page-monitor').length <= 0) return;

	initLatencyGraph();
	initCapacityGraph();
	getClusterMetrics();
}

//---

function getClusterMetrics() {
	setInterval(function() {
		$.ajax({
			url: '/cluster_metrics',
			type: 'GET'
		}).done(function(data) {
			var metrics = data.result;

			updateClusterStatus(metrics.cluster_status);

			updateClusterLatency({
				clusterStatus: metrics.cluster_status,
				latency: metrics.cluster_latency,
				fastAverageLatency: metrics.cluster_fast_average_latency,
				slowAverageLatency: metrics.cluster_slow_average_latency,
			});

			updateClusterCapacity({
				clusterStatus: metrics.cluster_status,
				capacity: metrics.cluster_capacity,
				usedCapacity: metrics.cluster_capacity_used,
				scaleUpCapacity: metrics.cluster_capacity_scale_up,
				scaleDownCapacity: metrics.cluster_capacity_scale_down
			});

			updateClusterOverview({
				clusterStatus: metrics.cluster_status,
				clusterNodes: metrics.cluster_nodes,
				memoryDistribution: metrics.cluster_memory_distribution
			});
		});
	}, refreshInterval);
}

//---

function updateClusterStatus(status) {	
	var element = $('#cluster-status span'),
		statusToDisplay = '';

	switch(status) {
		case 'not_configured':
			statusToDisplay = 'nicht konfiguriert';
			break;
		case 'configuring':
			statusToDisplay = 'wird konfiguriert';
			break;
		case 'configured':
			statusToDisplay = 'konfiguriert';
			break;
		case 'starting':
			statusToDisplay = 'wird gestartet';
			break;
		case 'online':
			statusToDisplay = 'online';
			break;
		case 'importing':
			statusToDisplay = 'am Importieren';
			break;
		case 'scaling_up':
			statusToDisplay = 'skaliert hoch';
			break;
		case 'scaling_down':
			statusToDisplay = 'skaliert herunter';
			break;
		case 'error':
			statusToDisplay = 'fehlerhaft';
			break;
	}

	element.html(statusToDisplay);
	element.removeClass().addClass(status);
}

//---

function updateClusterLatency(metrics) {	
	if (metrics.clusterStatus == 'online') {
		var newData = {};
		
		newData['Latency'] = metrics.latency;
		newData['Slow Average Latency'] = metrics.slowAverageLatency;
		newData['Fast Average Latency'] = metrics.fastAverageLatency;
		
		latencyGraph.series.addData(newData);
		latencyGraph.render();		
	}
}

//---

function updateClusterCapacity(metrics) {	
	if (metrics.clusterStatus == 'online' || metrics.clusterStatus == 'importing') {
		
		var newData = {};
		
		newData['Max. Capacity'] = parseFloat(metrics.capacity);
		newData['Used Capacity'] = parseFloat(metrics.usedCapacity);
		newData['Scale-Up Capacity'] = parseFloat(metrics.scaleUpCapacity);
		newData['Scale-Down Capacity'] = parseFloat(metrics.scaleDownCapacity);
		
		capacityGraph.series.addData(newData);
		capacityGraph.render();
	}
}

//---

function updateClusterOverview(metrics) {
	if (metrics.clusterStatus == 'online' || metrics.clusterStatus == 'importing' || metrics.clusterStatus == 'scaling_up' || metrics.clusterStatus == 'scaling_down') {
		
		var currentNodes = $('#cluster-nodes-container').html();
		
		if (currentNodes != metrics.clusterNodes) {
			$('#cluster-nodes-container').html(metrics.clusterNodes);
		}

		var currentMemory = $('#memory-distribution-container').html(),
			memoryDistribution = metrics.memoryDistribution; 
		
		if (currentMemory != memoryDistribution) {
			$('#memory-distribution-container').html(memoryDistribution);
		}
		
	} else {
		var msg = 'Cluster ist momentan nicht online!';

		$('#cluster-nodes-container').html(msg);
		$('#memory-distribution-container').html(' ');
	}
}

//---

function initLatencyGraph() {	
	latencyGraph = initGraph(
		'latency',
		'#cluster-latency-graph', 
		'ms', 
		'Latency'
	);

	latencyGraph.render();
}

//---

function initCapacityGraph() {	
	capacityGraph = initGraph(
		'capacity',
		'#cluster-capacity-graph', 
		'MB', 
		'Capacity'
	);
	
	capacityGraph.render();
}

//---

function initGraph(type, name, unit, info) {
	
	var height = 280,
		width = $($('.graph')[0]).width();

	width = (width == 0) ? 700 : width;

	var series = new Rickshaw.Series.FixedDuration([
		{ name: info, color: '#4991CB' }], undefined, {
			timeInterval: refreshInterval,
			maxDataPoints: 100,
			timeBase: new Date().getTime() / 1000
		});

	var graph = new Rickshaw.Graph({
		element: document.querySelector(name + ' #chart'),
		width: width,
		height: height,
		renderer: 'line',
		stroke: true,
		series: series
	});

	var xAxis = new Rickshaw.Graph.Axis.Time({
		graph: graph
	});

	var yTickFormat = function(y) {
		result = Rickshaw.Fixtures.Number.formatKMBT(y);
		result += (result != '') ? ' '+unit : '';			
		return result;
	};

	var yAxis = new Rickshaw.Graph.Axis.Y({
		graph: graph,
		orientation: 'left',
		height: height,
		tickFormat: yTickFormat,
		ticks: 10,
		element: $(name + ' #y_axis')[0]
	});

	var hoverDetail = new Rickshaw.Graph.HoverDetail( {
		graph: graph,
		formatter: function(series, x, y) {
			var date = '<span class="date">' + new Date(x * 1000).toUTCString() + '</span>';
			var swatch = '<span class="detail_swatch" style="background-color: ' + series.color + '"></span>';
			var content = swatch + series.name + ': ' + parseFloat(y).toFixed(3) + ' ' + unit;
			return content;
		}
	});

	$(window).resize(function() {
		var containerWidth = $($('.graph')[0]).width(),
			yAxisWidth = '80'; // px

		if (containerWidth != 0) {
			graph.configure({
				width: containerWidth - yAxisWidth
			});
			
			graph.render();
		}
	});

	return graph;
}