import React, { useState, useEffect } from 'react';
import { Card, Row, Col, Alert, Badge, Table, Button, Breadcrumb, Form } from 'react-bootstrap';
import { Link, useParams, useNavigate } from 'react-router-dom';
import { apiService, DomainGroup, Route, Domain } from '../services/api';
import { useNotification } from '../contexts/NotificationContext';
import ConfirmModal from './ConfirmModal';

const GroupDetails: React.FC = () => {
  const { groupName } = useParams<{ groupName: string }>();
  const navigate = useNavigate();
  const { showNotification } = useNotification();
  const [group, setGroup] = useState<DomainGroup | null>(null);
  const [routes, setRoutes] = useState<Route[]>([]);
  const [routerRoutes, setRouterRoutes] = useState<any[]>([]);
  const [routerRoutesLoading, setRouterRoutesLoading] = useState(false);
  const [routerRoutesError, setRouterRoutesError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [generating, setGenerating] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [editingGroupName, setEditingGroupName] = useState(false);
  const [groupNameValue, setGroupNameValue] = useState('');
  const [renaming, setRenaming] = useState(false);
  const [deletingDomain, setDeletingDomain] = useState<string | null>(null);
  const [newRegularDomain, setNewRegularDomain] = useState('');
  const [newFollowDnsDomain, setNewFollowDnsDomain] = useState('');
  const [addingDomain, setAddingDomain] = useState<string | null>(null);
  const [domainsWithTypes, setDomainsWithTypes] = useState<Domain[]>([]);

  useEffect(() => {
    const loadGroupDetails = async () => {
      if (!groupName) return;

      try {
        setLoading(true);

        // First try to get the group from the domain groups list (which has full data)
        const [allGroups, routesData] = await Promise.all([
          apiService.getDomainGroups(),
          apiService.getRoutes({ group_id: groupName })
        ]);

        const groupData = allGroups.find(g => g.name === groupName);

        if (!groupData) {
          // Fallback to individual group API if not found in list
          const individualGroupData = await apiService.getDomainGroup(groupName);

          // Convert the simplified format to our expected format
          const convertedGroup: DomainGroup = {
            id: 0, // We don't have the ID from this API
            name: groupName,
            mask: individualGroupData.settings?.mask || null,
            interfaces: individualGroupData.settings?.interfaces || null,
            domains: individualGroupData,
            statistics: {
              total_domains: (individualGroupData.domains?.length || 0) + (individualGroupData.follow_dns?.length || 0),
              regular_domains: individualGroupData.domains?.length || 0,
              follow_dns_domains: individualGroupData.follow_dns?.length || 0,
              total_routes: routesData.length,
              synced_routes: routesData.filter(r => r.synced_to_router).length,
              pending_routes: routesData.filter(r => !r.synced_to_router).length,
            },
          };

          setGroup(convertedGroup);
        } else {
          setGroup(groupData);
        }

        setRoutes(routesData);
        setError(null);
      } catch (err) {
        console.error('Failed to load group details:', err);
        setError(`Failed to load group details: ${err}`);
      } finally {
        setLoading(false);
      }
    };

    loadGroupDetails();
  }, [groupName]);

  useEffect(() => {
    if (group) {
      loadRouterRoutes();
      setGroupNameValue(group.name);
      loadGroupDomains();
    }
  }, [group]);

  const loadGroupDomains = async () => {
    if (!group || !group.id) return;

    try {
      const domainsData = await apiService.getGroupDomains(group.id);
      setDomainsWithTypes(domainsData.domains);
    } catch (err) {
      console.error('Failed to load group domains:', err);
      // Fallback to parsing from group.domains if API fails
      if (group && group.domains) {
        let regular: string[] = [];
        let followDns: string[] = [];
        
        if (Array.isArray(group.domains)) {
          regular = group.domains;
        } else if (typeof group.domains === 'object') {
          regular = group.domains.domains || [];
          followDns = group.domains.follow_dns || [];
        }
        
        const typedDomains: Domain[] = [
          ...regular.map((d: string, idx: number) => ({ id: idx, domain: d, type: 'regular' as const })),
          ...followDns.map((d: string, idx: number) => ({ id: idx + regular.length, domain: d, type: 'follow_dns' as const }))
        ];
        setDomainsWithTypes(typedDomains);
      }
    }
  };

  const formatDate = (dateString?: string) => {
    if (!dateString) return 'Never';
    const date = new Date(dateString);
    return date.toLocaleDateString() + ' ' + date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
  };

  const maskToCIDR = (mask: string): string => {
    // If already in CIDR format (starts with /), return as is
    if (mask.startsWith('/')) {
      return mask;
    }

    // Map of subnet masks to CIDR notation
    const maskToCIDRMap: { [key: string]: string } = {
      '255.0.0.0': '/8',
      '255.255.0.0': '/16',
      '255.255.128.0': '/17',
      '255.255.224.0': '/19',
      '255.255.240.0': '/20',
      '255.255.248.0': '/21',
      '255.255.252.0': '/22',
      '255.255.255.0': '/24',
      '255.255.255.128': '/25',
      '255.255.255.192': '/26',
      '255.255.255.224': '/27',
      '255.255.255.240': '/28',
      '255.255.255.248': '/29',
      '255.255.255.252': '/30',
      '255.255.255.254': '/31',
      '255.255.255.255': '/32',
    };

    return maskToCIDRMap[mask] || mask;
  };

  const ipToNumber = (ip: string): number => {
    return ip.split('.').reduce((acc, octet) => (acc << 8) + parseInt(octet, 10), 0);
  };

  const sortIPs = (routes: any[]): any[] => {
    return [...routes].sort((a, b) => {
      const ipA = a.network || a.dest || '';
      const ipB = b.network || b.dest || '';
      return ipToNumber(ipA) - ipToNumber(ipB);
    });
  };

  const loadRouterRoutes = async () => {
    if (!groupName) return;

    try {
      setRouterRoutesLoading(true);
      setRouterRoutesError(null);

      const result = await apiService.getRouterRoutes(groupName);

      if (result.success) {
        setRouterRoutes(result.routes || []);
      } else {
        setRouterRoutesError('Failed to load router routes');
      }
    } catch (err: any) {
      console.error('Error loading router routes:', err);
      setRouterRoutesError(err.response?.data?.error || err.message || 'Failed to load router routes');
    } finally {
      setRouterRoutesLoading(false);
    }
  };

  const handleGenerateIPs = async () => {
    if (!groupName) return;

    try {
      setGenerating(true);
      setError(null);

      const result = await apiService.generateIPs(groupName);

      if (result.success) {
        const message = `${result.message} (Added: ${result.statistics.added}, Deleted: ${result.statistics.deleted}, Total: ${result.statistics.total})`;
        showNotification('success', message);

        // Reload database routes immediately
        const updatedRoutes = await apiService.getRoutes({ group_id: groupName });
        setRoutes(updatedRoutes);

        // Refresh router routes
        await loadRouterRoutes();

        // Update group statistics if we have the group data
        if (group) {
          const updatedGroup = {
            ...group,
            statistics: {
              ...group.statistics,
              total_routes: result.statistics.total,
              synced_routes: updatedRoutes.filter(r => r.synced_to_router).length,
              pending_routes: updatedRoutes.filter(r => !r.synced_to_router).length,
            }
          };
          setGroup(updatedGroup);
        }
      }
    } catch (err: any) {
      console.error('Error generating IPs:', err);
      const errorMessage = err.response?.data?.error || err.message;
      setError(`Failed to generate IP addresses: ${errorMessage}`);
      showNotification('error', `Failed to generate IP addresses: ${errorMessage}`);
    } finally {
      setGenerating(false);
    }
  };

  const handleSyncToRouter = async () => {
    if (!groupName) return;

    try {
      setSyncing(true);
      setError(null);

      const result = await apiService.syncToRouter(groupName);

      if (result.success) {
        showNotification('success', result.message);

        // Reload the routes data to reflect sync status changes
        const updatedRoutes = await apiService.getRoutes({ group_id: groupName });
        setRoutes(updatedRoutes);

        // Update group statistics
        if (group) {
          const updatedGroup = {
            ...group,
            statistics: {
              ...group.statistics,
              synced_routes: updatedRoutes.filter(r => r.synced_to_router).length,
              pending_routes: updatedRoutes.filter(r => !r.synced_to_router).length,
            }
          };
          setGroup(updatedGroup);
        }

        // Refresh router routes to show newly synced routes
        await loadRouterRoutes();
      }
    } catch (err: any) {
      console.error('Error syncing to router:', err);
      const errorMessage = err.response?.data?.error || err.message;
      setError(`Failed to sync to router: ${errorMessage}`);
      showNotification('error', `Failed to sync to router: ${errorMessage}`);
    } finally {
      setSyncing(false);
    }
  };

  const handleDeleteClick = () => {
    setShowDeleteModal(true);
  };

  const handleDeleteConfirm = async () => {
    if (!groupName) return;

    setShowDeleteModal(false);

    try {
      setDeleting(true);
      setError(null);

      const result = await apiService.deleteDomainGroup(groupName);

      if (result.success) {
        showNotification('success', result.message || `Domain group "${groupName}" deleted successfully!`);
        navigate('/');
      }
    } catch (err: any) {
      console.error('Error deleting group:', err);
      const errorMessage = err.response?.data?.error || err.message;
      setError(`Failed to delete group: ${errorMessage}`);
      showNotification('error', `Failed to delete group: ${errorMessage}`);
    } finally {
      setDeleting(false);
    }
  };

  const handleDeleteCancel = () => {
    setShowDeleteModal(false);
  };

  const handleRenameGroup = async () => {
    if (!group || !groupNameValue.trim() || groupNameValue === group.name) {
      setEditingGroupName(false);
      setGroupNameValue(group?.name || '');
      return;
    }

    try {
      setRenaming(true);
      setError(null);

      await apiService.updateDomainGroupById(group.id, { name: groupNameValue.trim() });
      showNotification('success', `Group renamed to "${groupNameValue.trim()}" successfully!`);
      
      // Reload group data and navigate to new URL
      const updatedGroups = await apiService.getDomainGroups();
      const updatedGroup = updatedGroups.find(g => g.id === group.id);
      
      if (updatedGroup) {
        setGroup(updatedGroup);
        navigate(`/groups/${updatedGroup.name}`, { replace: true });
      }
      
      setEditingGroupName(false);
    } catch (err: any) {
      console.error('Error renaming group:', err);
      const errorMessage = err.response?.data?.error || err.message;
      setError(`Failed to rename group: ${errorMessage}`);
      showNotification('error', `Failed to rename group: ${errorMessage}`);
      setGroupNameValue(group.name);
    } finally {
      setRenaming(false);
    }
  };

  const handleAddDomain = async (domain: string, type: 'regular' | 'follow_dns' = 'regular') => {
    if (!group || !domain.trim()) return;

    const domainToAdd = domain.trim();
    try {
      setAddingDomain(domainToAdd);
      setError(null);

      await apiService.addDomainToGroup(group.id, domainToAdd, type);
      showNotification('success', `Domain "${domainToAdd}" added successfully!`);

      // Clear input
      if (type === 'regular') {
        setNewRegularDomain('');
      } else {
        setNewFollowDnsDomain('');
      }

      // Small delay to ensure database transaction is committed
      await new Promise(resolve => setTimeout(resolve, 100));

      // Reload domains with type information
      await loadGroupDomains();

      // Also reload group data and routes for statistics
      const [updatedGroups, updatedRoutes] = await Promise.all([
        apiService.getDomainGroups(),
        apiService.getRoutes({ group_id: group.name })
      ]);
      
      const updatedGroup = updatedGroups.find(g => g.id === group.id);
      
      if (updatedGroup) {
        setGroup(updatedGroup);
        setRoutes(updatedRoutes);
      } else {
        // Fallback: reload using the same logic as initial load
        const individualGroupData = await apiService.getDomainGroup(group.name);
        const convertedGroup: DomainGroup = {
          id: group.id,
          name: group.name,
          mask: individualGroupData.settings?.mask || null,
          interfaces: individualGroupData.settings?.interfaces || null,
          domains: individualGroupData,
          statistics: {
            total_domains: (individualGroupData.domains?.length || 0) + (individualGroupData.follow_dns?.length || 0),
            regular_domains: individualGroupData.domains?.length || 0,
            follow_dns_domains: individualGroupData.follow_dns?.length || 0,
            total_routes: updatedRoutes.length,
            synced_routes: updatedRoutes.filter(r => r.synced_to_router).length,
            pending_routes: updatedRoutes.filter(r => !r.synced_to_router).length,
          },
        };
        setGroup(convertedGroup);
        setRoutes(updatedRoutes);
      }
    } catch (err: any) {
      console.error('Error adding domain:', err);
      const errorMessage = err.response?.data?.error || err.message;
      setError(`Failed to add domain: ${errorMessage}`);
      showNotification('error', `Failed to add domain: ${errorMessage}`);
    } finally {
      setAddingDomain(null);
    }
  };

  const handleDeleteDomain = async (domain: string, type: 'regular' | 'follow_dns' = 'regular') => {
    if (!group) return;

    try {
      setDeletingDomain(domain);
      setError(null);

      await apiService.deleteDomainFromGroup(group.id, domain, type);
      showNotification('success', `Domain "${domain}" deleted successfully!`);

      // Reload domains with type information
      await loadGroupDomains();

      // Also reload group data and routes for statistics
      const [updatedGroups, updatedRoutes] = await Promise.all([
        apiService.getDomainGroups(),
        apiService.getRoutes({ group_id: group.name })
      ]);
      
      const updatedGroup = updatedGroups.find(g => g.id === group.id);
      
      if (updatedGroup) {
        setGroup(updatedGroup);
        setRoutes(updatedRoutes);
      } else {
        // Fallback: reload using the same logic as initial load
        const individualGroupData = await apiService.getDomainGroup(group.name);
        const convertedGroup: DomainGroup = {
          id: group.id,
          name: group.name,
          mask: individualGroupData.settings?.mask || null,
          interfaces: individualGroupData.settings?.interfaces || null,
          domains: individualGroupData,
          statistics: {
            total_domains: (individualGroupData.domains?.length || 0) + (individualGroupData.follow_dns?.length || 0),
            regular_domains: individualGroupData.domains?.length || 0,
            follow_dns_domains: individualGroupData.follow_dns?.length || 0,
            total_routes: updatedRoutes.length,
            synced_routes: updatedRoutes.filter(r => r.synced_to_router).length,
            pending_routes: updatedRoutes.filter(r => !r.synced_to_router).length,
          },
        };
        setGroup(convertedGroup);
        setRoutes(updatedRoutes);
      }
    } catch (err: any) {
      console.error('Error deleting domain:', err);
      const errorMessage = err.response?.data?.error || err.message;
      setError(`Failed to delete domain: ${errorMessage}`);
      showNotification('error', `Failed to delete domain: ${errorMessage}`);
    } finally {
      setDeletingDomain(null);
    }
  };

  const getDomainsList = () => {
    // Use domains with type information if available (preferred method)
    if (domainsWithTypes.length > 0) {
      return {
        regular: domainsWithTypes.filter(d => d.type === 'regular').map(d => d.domain),
        followDns: domainsWithTypes.filter(d => d.type === 'follow_dns').map(d => d.domain)
      };
    }

    // Fallback to parsing from group.domains structure
    if (!group || !group.domains) return { regular: [], followDns: [] };

    if (Array.isArray(group.domains)) {
      return { regular: group.domains, followDns: [] };
    }

    if (typeof group.domains === 'object') {
      return {
        regular: group.domains.domains || [],
        followDns: group.domains.follow_dns || []
      };
    }

    return { regular: [], followDns: [] };
  };

  const getDomainRouteInfo = (domainName: string) => {
    if (!routes) {
      return {
        dbRoutes: [],
        routerRoutes: [],
        isSynced: false,
        createdDate: null
      };
    }

    // Find database routes for this domain by parsing comment field
    // Comment format: [auto:group_name] domain_name
    const dbRoutesForDomain = routes.filter(route => {
      if (!route.comment) return false;
      const commentMatch = route.comment.match(/\[auto:[^\]]+\]\s*(.+)$/);
      return commentMatch && commentMatch[1] === domainName;
    });

    // Find router routes that match database routes by network/mask
    const routerRoutesForDomain = routerRoutes.filter(routerRoute => {
      return dbRoutesForDomain.some(dbRoute => {
        const routerNetwork = routerRoute.network || routerRoute.dest;
        const routerMask = routerRoute.mask || routerRoute.genmask || '255.255.255.255';
        return routerNetwork === dbRoute.network && routerMask === dbRoute.mask;
      });
    });

    // Check if all database routes are synced
    const isSynced = dbRoutesForDomain.length > 0 && 
      dbRoutesForDomain.every(route => route.synced_to_router) &&
      dbRoutesForDomain.length === routerRoutesForDomain.length;

    // Get earliest created date from routes
    const createdDate = dbRoutesForDomain.length > 0
      ? dbRoutesForDomain.reduce((earliest, route) => {
          const routeDate = route.created_at ? new Date(route.created_at) : null;
          if (!earliest) return routeDate;
          if (!routeDate) return earliest;
          return routeDate < earliest ? routeDate : earliest;
        }, null as Date | null)
      : null;

    return {
      dbRoutes: dbRoutesForDomain,
      routerRoutes: routerRoutesForDomain,
      isSynced,
      createdDate
    };
  };

  if (loading) {
    return (
      <div className="text-center py-5">
        <div className="loading-spinner me-2"></div>
        Loading group details...
      </div>
    );
  }

  if (!loading && !group) {
    return (
      <>
        <Breadcrumb>
          <Breadcrumb.Item linkAs={Link} linkProps={{ to: '/' }}>Domain Groups</Breadcrumb.Item>
          <Breadcrumb.Item active>{groupName}</Breadcrumb.Item>
        </Breadcrumb>

        <Alert variant="danger">
          Group not found
        </Alert>

        <Link to="/" className="btn btn-primary">
          <i className="fas fa-arrow-left me-2"></i>
          Back to Groups
        </Link>
      </>
    );
  }

  const domains = getDomainsList();

  if (!group) {
    return null; // This shouldn't happen due to the check above, but TypeScript needs it
  }

  return (
    <>
      <Breadcrumb>
        <Breadcrumb.Item linkAs={Link} linkProps={{ to: '/' }}>Domain Groups</Breadcrumb.Item>
        <Breadcrumb.Item active>{group.name}</Breadcrumb.Item>
      </Breadcrumb>

      <Row>
        <Col>
          <div className="d-flex justify-content-between align-items-center mb-4">
            <div className="d-flex align-items-center">
              <i className="fas fa-layer-group me-2"></i>
              {editingGroupName ? (
                <div className="d-flex align-items-center">
                  <Form.Control
                    type="text"
                    value={groupNameValue}
                    onChange={(e) => setGroupNameValue(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') {
                        handleRenameGroup();
                      } else if (e.key === 'Escape') {
                        setEditingGroupName(false);
                        setGroupNameValue(group.name);
                      }
                    }}
                    onBlur={handleRenameGroup}
                    autoFocus
                    disabled={renaming}
                    style={{ width: '300px' }}
                  />
                  {renaming && (
                    <div className="loading-spinner ms-2"></div>
                  )}
                </div>
              ) : (
                <h1 className="mb-0">
                  {group.name}
                  <Button
                    variant="link"
                    size="sm"
                    className="ms-2 p-0"
                    onClick={() => setEditingGroupName(true)}
                    title="Rename group"
                    style={{ fontSize: '0.8em', verticalAlign: 'middle' }}
                  >
                    <i className="fas fa-edit"></i>
                  </Button>
                </h1>
              )}
            </div>
            <div>
              <Link to="/" className="btn btn-outline-secondary me-2">
                <i className="fas fa-arrow-left me-1"></i>
                Back to Groups
              </Link>
              <Button
                variant="success"
                className="me-2"
                onClick={handleGenerateIPs}
                disabled={generating || syncing || deleting || renaming || editingGroupName}
              >
                {generating ? (
                  <>
                    <div className="loading-spinner me-2"></div>
                    Generating...
                  </>
                ) : (
                  <>
                    <i className="fas fa-sync-alt me-1"></i>
                    Generate IPs
                  </>
                )}
              </Button>
              <Button
                variant="warning"
                className="me-2"
                onClick={handleSyncToRouter}
                disabled={generating || syncing || deleting || renaming || editingGroupName}
              >
                {syncing ? (
                  <>
                    <div className="loading-spinner me-2"></div>
                    Syncing...
                  </>
                ) : (
                  <>
                    <i className="fas fa-upload me-1"></i>
                    Sync to Router
                    {group.statistics.pending_routes > 0 && (
                      <Badge bg="light" text="dark" className="ms-1">
                        {group.statistics.pending_routes}
                      </Badge>
                    )}
                  </>
                )}
              </Button>
              <Link
                to={`/ip-addresses?group_id=${group.id}`}
                className="btn btn-primary me-2"
              >
                <i className="fas fa-network-wired me-1"></i>
                View All Routes
              </Link>
              <Button
                variant="danger"
                onClick={handleDeleteClick}
                disabled={generating || syncing || deleting || renaming || editingGroupName}
              >
                {deleting ? (
                  <>
                    <div className="loading-spinner me-2"></div>
                    Deleting...
                  </>
                ) : (
                  <>
                    <i className="fas fa-trash me-1"></i>
                    Delete Group
                  </>
                )}
              </Button>
            </div>
          </div>
        </Col>
      </Row>

      {/* Error Messages */}
      {error && (
        <Alert variant="danger" className="mb-4" dismissible onClose={() => setError(null)}>
          <i className="fas fa-exclamation-triangle me-2"></i>
          {error}
        </Alert>
      )}

      <Row className="mb-4">
        <Col lg={4}>
          <Card className="h-100">
            <Card.Header>
              <h6 className="mb-0">
                <i className="fas fa-cog me-2"></i>
                Configuration
              </h6>
            </Card.Header>
            <Card.Body>
              {group.mask && (
                <div className="mb-3">
                  <div className="small text-muted mb-1">Network Mask</div>
                  <code className="text-primary">{group.mask}</code>
                </div>
              )}

              {group.interfaces && (
                <div className="mb-3">
                  <div className="small text-muted mb-1">Interface</div>
                  <Badge bg="info">{group.interfaces}</Badge>
                </div>
              )}

              <div className="mb-3">
                <div className="small text-muted mb-1">Created</div>
                <div className="text-dark">
                  <i className="fas fa-calendar-plus me-1 text-success"></i>
                  {formatDate(group.created_at)}
                </div>
              </div>

              <div>
                <div className="small text-muted mb-1">Last Updated</div>
                <div className="text-dark">
                  <i className="fas fa-clock me-1 text-warning"></i>
                  {formatDate(group.updated_at)}
                </div>
              </div>
            </Card.Body>
          </Card>
        </Col>

        <Col lg={8}>
          <Card className="h-100">
            <Card.Header>
              <h6 className="mb-0">
                <i className="fas fa-chart-pie me-2"></i>
                Overview Statistics
              </h6>
            </Card.Header>
            <Card.Body>
              <Row className="text-center mb-4">
                <Col xs={6} md={3}>
                  <div className="p-3 bg-primary bg-opacity-10 rounded mb-2">
                    <div className="h3 mb-1 text-primary">{group.statistics.total_domains}</div>
                    <div className="text-muted small fw-bold">Total Domains</div>
                  </div>
                </Col>
                <Col xs={6} md={3}>
                  <div className="p-3 bg-info bg-opacity-10 rounded mb-2">
                    <div className="h3 mb-1 text-info">{group.statistics.total_routes}</div>
                    <div className="text-muted small fw-bold">IP Routes</div>
                  </div>
                </Col>
                <Col xs={6} md={3}>
                  <div className="p-3 bg-success bg-opacity-10 rounded mb-2">
                    <div className="h3 mb-1 text-success">{group.statistics.synced_routes}</div>
                    <div className="text-muted small fw-bold">Synced</div>
                  </div>
                </Col>
                <Col xs={6} md={3}>
                  <div className="p-3 bg-warning bg-opacity-10 rounded mb-2">
                    <div className="h3 mb-1 text-warning">{group.statistics.pending_routes}</div>
                    <div className="text-muted small fw-bold">Pending</div>
                  </div>
                </Col>
              </Row>

              <Row className="text-center">
                <Col xs={6}>
                  <div className="p-2 border rounded">
                    <div className="h5 mb-1 text-primary">{group.statistics.regular_domains}</div>
                    <div className="text-muted small">
                      <i className="fas fa-globe me-1"></i>
                      Regular Domains
                    </div>
                  </div>
                </Col>
                {group.statistics.follow_dns_domains > 0 && (
                  <Col xs={6}>
                    <div className="p-2 border rounded">
                      <div className="h5 mb-1 text-success">{group.statistics.follow_dns_domains}</div>
                      <div className="text-muted small">
                        <i className="fas fa-eye me-1"></i>
                        DNS Monitored
                      </div>
                    </div>
                  </Col>
                )}
                {group.statistics.follow_dns_domains === 0 && (
                  <Col xs={6}>
                    <div className="p-2 border rounded bg-light">
                      <div className="h5 mb-1 text-muted">0</div>
                      <div className="text-muted small">
                        <i className="fas fa-eye me-1"></i>
                        DNS Monitored
                      </div>
                    </div>
                  </Col>
                )}
              </Row>
            </Card.Body>
          </Card>
        </Col>
      </Row>

      {/* Regular Domains */}
      <Row className="mb-4">
        <Col>
          <Card>
            <Card.Header>
              <h6 className="mb-0">
                <i className="fas fa-globe me-2"></i>
                Regular Domains ({domains.regular.length})
              </h6>
            </Card.Header>
            <Card.Body>
              {/* Add new domain input */}
              <div className="mb-3">
                <div className="d-flex">
                  <Form.Control
                    type="text"
                    placeholder="Enter domain name (e.g., example.com)"
                    value={newRegularDomain}
                    onChange={(e) => setNewRegularDomain(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter' && newRegularDomain.trim()) {
                        handleAddDomain(newRegularDomain, 'regular');
                      }
                    }}
                    disabled={addingDomain !== null}
                    className="me-2"
                  />
                  <Button
                    variant="primary"
                    onClick={() => handleAddDomain(newRegularDomain, 'regular')}
                    disabled={!newRegularDomain.trim() || addingDomain !== null}
                  >
                    {addingDomain === newRegularDomain.trim() ? (
                      <>
                        <div className="loading-spinner me-2"></div>
                        Adding...
                      </>
                    ) : (
                      <>
                        <i className="fas fa-plus me-1"></i>
                        Add
                      </>
                    )}
                  </Button>
                </div>
              </div>

              {/* Domain table */}
              {domains.regular.length > 0 ? (
                <div className="table-responsive">
                  <Table hover className="mb-0">
                    <thead className="table-light">
                      <tr>
                        <th>Domain Name</th>
                        <th>When Added</th>
                        <th>IP Addresses in Database</th>
                        <th>IP Addresses in Router</th>
                        <th>Sync Status</th>
                        <th>Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      {domains.regular.map((domain: string, index: number) => {
                        const routeInfo = getDomainRouteInfo(domain);

                        return (
                          <tr key={index}>
                            <td>
                              <i className="fas fa-globe fa-xs me-2 text-primary"></i>
                              <code className="text-primary">{domain}</code>
                            </td>
                            <td>
                              {routeInfo.createdDate ? (
                                <small className="text-muted">
                                  {formatDate(routeInfo.createdDate.toISOString())}
                                </small>
                              ) : (
                                <span className="text-muted">-</span>
                              )}
                            </td>
                            <td>
                              {routeInfo.dbRoutes.length > 0 ? (
                                <div>
                                  {sortIPs(routeInfo.dbRoutes).map((route, idx) => (
                                    <div key={idx} className="mb-1">
                                      <Badge bg="info">
                                        {route.network}{maskToCIDR(route.mask)}
                                      </Badge>
                                    </div>
                                  ))}
                                </div>
                              ) : (
                                <span className="text-muted">-</span>
                              )}
                            </td>
                            <td>
                              {routeInfo.routerRoutes.length > 0 ? (
                                <div>
                                  {sortIPs(routeInfo.routerRoutes).map((route, idx) => {
                                    const network = route.network || route.dest;
                                    const mask = route.mask || route.genmask || '255.255.255.255';
                                    return (
                                      <div key={idx} className="mb-1">
                                        <Badge bg="success">
                                          {network}{maskToCIDR(mask)}
                                        </Badge>
                                      </div>
                                    );
                                  })}
                                </div>
                              ) : (
                                <span className="text-muted">-</span>
                              )}
                            </td>
                            <td>
                              {routeInfo.dbRoutes.length > 0 ? (
                                routeInfo.isSynced ? (
                                  <span className="status-badge status-synced">
                                    <i className="fas fa-check me-1"></i>Synced
                                  </span>
                                ) : (
                                  <span className="status-badge status-unsynced">
                                    <i className="fas fa-times me-1"></i>Not Synced
                                  </span>
                                )
                              ) : (
                                <span className="text-muted">No routes</span>
                              )}
                            </td>
                            <td>
                              <Button
                                variant="link"
                                size="sm"
                                className="text-muted p-0"
                                onClick={() => handleDeleteDomain(domain, 'regular')}
                                disabled={deletingDomain === domain}
                                title="Delete domain"
                              >
                                {deletingDomain === domain ? (
                                  <div className="loading-spinner" style={{ width: '12px', height: '12px' }}></div>
                                ) : (
                                  <i className="fas fa-trash"></i>
                                )}
                              </Button>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </Table>
                </div>
              ) : (
                <div className="text-muted text-center py-3">
                  <i className="fas fa-info-circle me-2"></i>
                  No regular domains yet. Add one above.
                </div>
              )}
            </Card.Body>
          </Card>
        </Col>
      </Row>

      {/* DNS Follow Domains */}
      <Row className="mb-4">
        <Col>
          <Card>
            <Card.Header>
              <h6 className="mb-0">
                <i className="fas fa-eye me-2"></i>
                DNS Monitored Domains ({domains.followDns.length})
              </h6>
            </Card.Header>
            <Card.Body>
              {/* Add new domain input */}
              <div className="mb-3">
                <div className="d-flex">
                  <Form.Control
                    type="text"
                    placeholder="Enter domain name (e.g., example.com)"
                    value={newFollowDnsDomain}
                    onChange={(e) => setNewFollowDnsDomain(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter' && newFollowDnsDomain.trim()) {
                        handleAddDomain(newFollowDnsDomain, 'follow_dns');
                      }
                    }}
                    disabled={addingDomain !== null}
                    className="me-2"
                  />
                  <Button
                    variant="success"
                    onClick={() => handleAddDomain(newFollowDnsDomain, 'follow_dns')}
                    disabled={!newFollowDnsDomain.trim() || addingDomain !== null}
                  >
                    {addingDomain === newFollowDnsDomain.trim() ? (
                      <>
                        <div className="loading-spinner me-2"></div>
                        Adding...
                      </>
                    ) : (
                      <>
                        <i className="fas fa-plus me-1"></i>
                        Add
                      </>
                    )}
                  </Button>
                </div>
              </div>

              {/* Domain list */}
              {domains.followDns.length > 0 ? (
                <Row>
                  {domains.followDns.map((domain: string, index: number) => (
                    <Col key={index} md={6} lg={4} className="mb-2">
                      <div className="domain-item d-flex justify-content-between align-items-center">
                        <span>
                          <i className="fas fa-eye fa-xs me-2 text-success"></i>
                          {domain}
                        </span>
                        <Button
                          variant="link"
                          size="sm"
                          className="text-muted p-0 ms-2"
                          onClick={() => handleDeleteDomain(domain, 'follow_dns')}
                          disabled={deletingDomain === domain}
                          title="Delete domain"
                        >
                          {deletingDomain === domain ? (
                            <div className="loading-spinner" style={{ width: '12px', height: '12px' }}></div>
                          ) : (
                            <i className="fas fa-trash"></i>
                          )}
                        </Button>
                      </div>
                    </Col>
                  ))}
                </Row>
              ) : (
                <div className="text-muted text-center py-3">
                  <i className="fas fa-info-circle me-2"></i>
                  No DNS monitored domains yet. Add one above.
                </div>
              )}
            </Card.Body>
          </Card>
        </Col>
      </Row>

      {/* IP Routes in Database */}
      <Row className="mb-4">
        <Col>
          <Card>
            <Card.Header>
              <h6 className="mb-0">
                <i className="fas fa-database me-2"></i>
                IP Routes in Database ({routes.length})
              </h6>
            </Card.Header>
            <Card.Body className="p-0">
              {routes.length === 0 ? (
                <div className="text-center py-4">
                  <i className="fas fa-info-circle fa-2x text-muted mb-3"></i>
                  <p className="text-muted">No IP routes found for this group</p>
                </div>
              ) : (
                <div className="table-responsive">
                  <Table hover className="mb-0">
                    <thead className="table-light">
                      <tr>
                        <th>Network</th>
                        <th>Mask</th>
                        <th>Interface</th>
                        <th>Sync Status</th>
                        <th>Last Sync</th>
                        <th>Comment</th>
                      </tr>
                    </thead>
                    <tbody>
                      {routes.map((route: Route) => (
                        <tr key={route.id}>
                          <td>
                            <code className="text-primary">{route.network}</code>
                          </td>
                          <td>
                            <code className="text-muted">{route.mask}</code>
                          </td>
                          <td>
                            {route.interface ? (
                              <Badge bg="info">{route.interface}</Badge>
                            ) : (
                              <span className="text-muted">-</span>
                            )}
                          </td>
                          <td>
                            {route.synced_to_router ? (
                              <span className="status-badge status-synced">
                                <i className="fas fa-check me-1"></i>Synced
                              </span>
                            ) : (
                              <span className="status-badge status-unsynced">
                                <i className="fas fa-times me-1"></i>Not Synced
                              </span>
                            )}
                          </td>
                          <td>
                            <small className="text-muted">
                              <i className="fas fa-clock me-1"></i>
                              {formatDate(route.synced_at)}
                            </small>
                          </td>
                          <td>
                            {route.comment ? (
                              <small className="text-muted">{route.comment}</small>
                            ) : (
                              <span className="text-muted">-</span>
                            )}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </Table>
                </div>
              )}
            </Card.Body>
          </Card>
        </Col>
      </Row>

      {/* Router Routes Section */}
      <Row>
        <Col>
          <Card>
            <Card.Header>
              <div className="d-flex justify-content-between align-items-center">
                <h6 className="mb-0">
                  <i className="fas fa-router me-2"></i>
                  IP Routes in Router ({routerRoutes.length})
                </h6>
                <Button
                  variant="outline-secondary"
                  size="sm"
                  onClick={loadRouterRoutes}
                  disabled={routerRoutesLoading}
                >
                  {routerRoutesLoading ? (
                    <>
                      <div className="loading-spinner me-1"></div>
                      Loading...
                    </>
                  ) : (
                    <>
                      <i className="fas fa-refresh me-1"></i>
                      Refresh
                    </>
                  )}
                </Button>
              </div>
            </Card.Header>
            <Card.Body className="p-0">
              {routerRoutesError ? (
                <div className="text-center py-4">
                  <i className="fas fa-exclamation-triangle fa-2x text-danger mb-3"></i>
                  <p className="text-danger">{routerRoutesError}</p>
                  <Button variant="outline-primary" size="sm" onClick={loadRouterRoutes}>
                    <i className="fas fa-retry me-1"></i>
                    Retry
                  </Button>
                </div>
              ) : routerRoutesLoading ? (
                <div className="text-center py-4">
                  <div className="loading-spinner me-2"></div>
                  Loading router routes...
                </div>
              ) : routerRoutes.length === 0 ? (
                <div className="text-center py-4">
                  <i className="fas fa-info-circle fa-2x text-muted mb-3"></i>
                  <p className="text-muted">No matching routes found in router for this group</p>
                  <small className="text-muted">Routes may not be synced yet or router may be unreachable</small>
                </div>
              ) : (
                <div className="table-responsive">
                  <Table hover className="mb-0">
                    <thead className="table-light">
                      <tr>
                        <th>Network</th>
                        <th>Mask</th>
                        <th>Interface</th>
                        <th>Gateway</th>
                        <th>Metric</th>
                        <th>Protocol</th>
                        <th>Type</th>
                      </tr>
                    </thead>
                    <tbody>
                      {routerRoutes.map((route: any, index: number) => (
                        <tr key={index}>
                          <td>
                            <code className="text-primary">{route.network || '-'}</code>
                          </td>
                          <td>
                            <code className="text-muted">{route.mask || '-'}</code>
                          </td>
                          <td>
                            {route.interface ? (
                              <Badge bg="info">{route.interface}</Badge>
                            ) : (
                              <span className="text-muted">-</span>
                            )}
                          </td>
                          <td>
                            <code className="text-secondary">{route.gateway || '-'}</code>
                          </td>
                          <td>
                            <Badge bg="secondary">{route.metric || '0'}</Badge>
                          </td>
                          <td>
                            <Badge bg="success">{route.proto || 'unknown'}</Badge>
                          </td>
                          <td>
                            <span className="text-muted">{route.type || 'unicast'}</span>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </Table>
                </div>
              )}
            </Card.Body>
          </Card>
        </Col>
      </Row>

      <ConfirmModal
        show={showDeleteModal}
        title="Delete Domain Group"
        message={`Are you sure you want to delete the domain group "${groupName}"? This action cannot be undone.`}
        confirmText="Delete"
        cancelText="Cancel"
        variant="danger"
        onConfirm={handleDeleteConfirm}
        onCancel={handleDeleteCancel}
      />
    </>
  );
};

export default GroupDetails;
