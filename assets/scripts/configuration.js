///////////////////////////////////////////////////////////////////////////////
//
// Configuration.js
//
///////////////////////////////////////////////////////////////////////////////


function initConfiguration() {
	if ($('#page-configuration').length <= 0) return;

	initSortableList('ol.simple_with_animation');
	initAddNodeGroupButton();
	initSaveClusterNodeChanges();
}

//---

function initSortableList(selector) {
	var adjustment;

	$(selector).sortable({
		group: 'simple_with_animation',
		pullPlaceholder: false,
		
		// Validation
		isValidTarget: function(item, container) {
			var maxNodes = parseInt($(container.el).data('max-nodes'));
			return (container.items.length < maxNodes);
		},
		
		// Animation on drop
		onDrop: function(item, targetContainer, _super) {
			var clonedItem = $('<li/>').css({height: 0});
			
			item.before(clonedItem);
			
			clonedItem.animate({'height': item.height()});

			item.animate(clonedItem.position(), function() {
				clonedItem.detach();
				_super(item);
			});
		},
		
		// Set item relative to the cursor position
		onDragStart: function($item, container, _super) {
			var offset = $item.offset(),
				pointer = container.rootGroup.pointer;

			adjustment = {
				left: pointer.left - offset.left,
				top: pointer.top - offset.top
			};

			_super($item, container);
		},
		
		// Drag handler
		onDrag: function ($item, position) {
			$item.css({
				left: position.left - adjustment.left,
				top: position.top - adjustment.top
			});
		}
	});

	// Delte node group (transfer nodes into inactive group)
	$('.delete-node-group').unbind('click');

	$('.delete-node-group').click(function() {
		var nodeContainer = $(this).parent();

		transferNodesIntoInactive(nodeContainer);
		nodeContainer.remove();

		// Fix the node group numbering
		var nodeGroupNumber = 0;

		$('#node-groups .node-group').each(function() {
			var nodeGroup = $(this);
			nodeGroup.attr('id', 'node-group-'+nodeGroupNumber);
			nodeGroup.attr('data-node-group', nodeGroupNumber);
			nodeGroup.find('span').html('Node Group ' + nodeGroupNumber);
			nodeGroupNumber++;
		});
	});
}

//---

function initAddNodeGroupButton() {
	$('#add-node-group').click(function() {
		var nodeGroup = getNodeGroupCount();

		var html = '<ol id="node-group-'+nodeGroup+'" data-node-group="'+nodeGroup+'" ';
			html+= 'class="node-group simple_with_animation vertical" '; 
			html+= 'data-max-nodes="99"> ';
			html+= 		'<span>Node Group '+nodeGroup+'</span> <a id="delete-node-group" class="delete-node-group">x</a>';
			html+= '</ol>';
		$('#node-groups').append(html);

		var ng = '#node-group-' + nodeGroup

		initSortableList(ng);
	});
}

//---

function getNodeGroupCount() {
	return $('.node-group').length;
}

//---

function transferNodesIntoInactive(nodeContainer) {
	var nodes = nodeContainer.find('li');
	nodes.appendTo('#inactive-data-nodes');
}

//---

function getNodes(selector) {
	var rawNodes = $(selector).find('li'),
		nodes = [];
	
	rawNodes.each(function() {
		nodes.push({
			id: $(this).data('id'),
			displayname: $(this).data('displayname'),
			name: $(this).data('name'),
			ip: $(this).data('ip')
		});
	});

	return nodes;
}

//---

function getDataNodes() {
	var dataNodes = [];

	// Filter inactive nodes
	var inactiveNodes = $('#inactive-data-nodes li');
	
	inactiveNodes = inactiveNodes.map(function() {
		var node = $(this);

		return {
			id: node.data('id'),
			displayname: node.data('displayname'),
			name: node.data('name'),
			ip: node.data('ip'),
			nodegroup: 65536 // required by MySQL Cluster				
		};
	});

	dataNodes = $.merge(dataNodes, inactiveNodes);

	// Filter node group nodes
	var nodeGroups = $('#node-groups ol'),
		nodeGroupNodes = [];

	nodeGroups.each(function() {
		var nodeGroup = $(this);

		nodeGroup.find('li').each(function() {
			var node = $(this);

			nodeGroupNodes.push({
				id: node.data('id'),
				displayname: node.data('displayname'),
				name: node.data('name'),
				ip: node.data('ip'),
				nodegroup: nodeGroup.data('node-group')
			});
		});
	});

	dataNodes = $.merge(dataNodes, nodeGroupNodes);
	
	return dataNodes;
}

//---

function validateNodes(managementNode, sqlNodes, dataNodes, loadBalancerNode) {
	var valid = 'alles ok',
		error = '';
	
	// Validation
	if (managementNode.length != 1) {
		error += 'Genau 1x Management-Node wird benötigt. \n';
	}

	if (sqlNodes.length < 1) {
		error += 'Mind. 1x SQL-Node wird benötigt. \n';
	}

	if (dataNodes.length < 1) {
		error += 'Mind. 1x Data-Node wird benötigt. \n';
	}

	if (loadBalancerNode < 0) {
		error += 'Max. 1x Load-Balancer-Node möglich \n';
	}
	
	// Gather node group information
	var nodeCountsPerGroup = [];

	$('#node-groups .node-group').each(function() {
		var nodeGroup = $(this);
		nodeCountsPerGroup.push(nodeGroup.find('li').length);
	});

	// At least 1x Node Group has to be created
	if (nodeCountsPerGroup.length < 1) {
		error += 'Mind. 1x Node Group muss vorhanden sein. \n';
	}

	// Check for empty node groups
	if ($.inArray(0, nodeCountsPerGroup) !== -1) {
		error += 'Keine leeren Node Groups erlaubt. \n';
	}

	// Check for same node counts in groups
	if (nodeCountsPerGroup.unique().length > 1) {
		error += 'Anzahl der Data-Nodes pro Node Group muss gleich sein. \n';
	}

	return (error != '') ? error : valid;
}

//---

function initSaveClusterNodeChanges() {
	$('#save-cluster-node-changes').click(function() {
		var continueSaving = confirm('Der Cluster wird bei Änderungen komplett neu gestartet. \n Trotzdem fortfahren?');

		if (continueSaving)  {
			var managementNode = getNodes('#cluster-management-node'),
				sqlNodes = getNodes('#cluster-sql-nodes'),
				dataNodes = getDataNodes(),
				loadBalancerNode = getNodes('#cluster-load-balancer-node');

			var validation = validateNodes(managementNode, sqlNodes, dataNodes, loadBalancerNode); 

			if (validation == 'alles ok') {
				$('.ajax-loader-container').fadeIn(500);
				$.ajax({
					url: '/configure_cluster',
					type: 'GET',
					data: {
						managementNode: 	managementNode,
						sqlNodes: 			sqlNodes,
						dataNodes: 			dataNodes,
						loadBalancerNode: 	loadBalancerNode
					}
				}).done(function(data) {
					$('.ajax-loader-container').fadeOut(500);
					var result = data.result;
					if (result == 'updated') {
						alert('Konfiguration gespeichert. Cluster wird neu gestartet.')
					} else if (result == 'no_changes') {
						alert('Keine Änderungen an der Konfiguration festgestellt.');
					}
				});
			} else {
				alert('Konfiguration inkorrekt.');
				alert(validation);
			}
		}
	});	
}