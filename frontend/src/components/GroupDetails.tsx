import React, { useState, useEffect } from 'react';
import { Card, Row, Col, Alert, Badge, Table, Button, Breadcrumb, Form } from 'react-bootstrap';
import { Link, useParams, useNavigate } from 'react-router-dom';
import { apiService, DomainGroup, Domain } from '../services/api';
import { useNotification } from '../contexts/NotificationContext';
import ConfirmModal from './ConfirmModal';

const GroupDetails: React.FC = () => {
  const { groupName } = useParams<{ groupName: string }>();
  const navigate = useNavigate();
  const { showNotification } = useNotification();
  const [group, setGroup] = useState<DomainGroup | null>(null);
  const [routerRoutes, setRouterRoutes] = useState<any[]>([]);
  const [routerRoutesLoading, setRouterRoutesLoading] = useState(false);
  const [routerRoutesError, setRouterRoutesError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [editingGroupName, setEditingGroupName] = useState(false);
  const [groupNameValue, setGroupNameValue] = useState('');
  const [renaming, setRenaming] = useState(false);
  const [deletingDomain, setDeletingDomain] = useState<string | null>(null);
  const [newFollowDnsDomain, setNewFollowDnsDomain] = useState('');
  const [addingDomain, setAddingDomain] = useState<string | null>(null);
  const [domainsWithTypes, setDomainsWithTypes] = useState<Domain[]>([]);
  const [editingConfig, setEditingConfig] = useState(false);
  const [maskValue, setMaskValue] = useState('');
  const [interfacesValue, setInterfacesValue] = useState('');
  const [updatingConfig, setUpdatingConfig] = useState(false);
  const [routerInterfaces, setRouterInterfaces] = useState<Array<{ id: string; description: string; name: string }>>([]);
  const [loadingInterfaces, setLoadingInterfaces] = useState(false);
  const [showDeleteRoutesModal, setShowDeleteRoutesModal] = useState(false);
  const [deletingRoutes, setDeletingRoutes] = useState(false);

  useEffect(() => {
    const loadGroupDetails = async () => {
      if (!groupName) return;

      try {
        setLoading(true);

        // First try to get the group from the domain groups list (which has full data)
        const allGroups = await apiService.getDomainGroups();
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
              total_domains: individualGroupData.follow_dns?.length || 0,
              regular_domains: 0,
              follow_dns_domains: individualGroupData.follow_dns?.length || 0,
              total_routes: 0,
              synced_routes: 0,
              pending_routes: 0,
            },
          };

          setGroup(convertedGroup);
        } else {
          setGroup(groupData);
        }
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
      setMaskValue(group.mask || '');
      setInterfacesValue(group.interfaces || '');
      loadGroupDomains();
    }
  }, [group]);

  const loadRouterInterfaces = async () => {
    try {
      setLoadingInterfaces(true);
      const result = await apiService.getRouterInterfaces();
      
      if (result.success && result.interfaces) {
        setRouterInterfaces(result.interfaces);
      }
    } catch (err: any) {
      console.error('Failed to load router interfaces:', err);
      // Don't show error notification, just log it
    } finally {
      setLoadingInterfaces(false);
    }
  };

  useEffect(() => {
    // Load interfaces when component mounts or when group changes
    loadRouterInterfaces();
  }, []);

  useEffect(() => {
    // Also reload interfaces when entering edit mode to ensure fresh data
    if (editingConfig) {
      loadRouterInterfaces();
    }
  }, [editingConfig]);

  const loadGroupDomains = async () => {
    if (!group || !group.id) return;

    try {
      const domainsData = await apiService.getGroupDomains(group.id);
      setDomainsWithTypes(domainsData.domains);
    } catch (err) {
      console.error('Failed to load group domains:', err);
        // Fallback to parsing from group.domains if API fails
        if (group && group.domains) {
          let followDns: string[] = [];
          
          if (Array.isArray(group.domains)) {
            // Legacy format - treat as follow_dns
            followDns = group.domains;
          } else if (typeof group.domains === 'object') {
            followDns = group.domains.follow_dns || [];
          }
          
          const typedDomains: Domain[] = [
            ...followDns.map((d: string, idx: number) => ({ id: idx, domain: d, type: 'follow_dns' as const }))
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
    if (!groupName || !group) return;

    try {
      setRouterRoutesLoading(true);
      setRouterRoutesError(null);

      // Load routes directly from router (filtered by group_name on backend)
      const result = await apiService.getAllRouterRoutes({ group_name: groupName });

      if (result.success) {
        setRouterRoutes(result.routes || []);
      } else {
        setRouterRoutesError(result.error || 'Failed to load router routes');
      }
    } catch (err: any) {
      console.error('Error loading router routes:', err);
      setRouterRoutesError(err.response?.data?.error || err.message || 'Failed to load router routes');
    } finally {
      setRouterRoutesLoading(false);
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

  const handleSaveConfig = async () => {
    if (!group) return;

    try {
      setUpdatingConfig(true);
      setError(null);

      await apiService.updateDomainGroupById(group.id, {
        mask: maskValue.trim() || '',
        interfaces: interfacesValue.trim() || ''
      });
      
      showNotification('success', 'Configuration updated successfully!');
      
      // Reload group data
      const updatedGroups = await apiService.getDomainGroups();
      const updatedGroup = updatedGroups.find(g => g.id === group.id);
      
      if (updatedGroup) {
        setGroup(updatedGroup);
        setMaskValue(updatedGroup.mask || '');
        setInterfacesValue(updatedGroup.interfaces || '');
      }
      
      setEditingConfig(false);
    } catch (err: any) {
      console.error('Error updating configuration:', err);
      const errorMessage = err.response?.data?.error || err.message;
      setError(`Failed to update configuration: ${errorMessage}`);
      showNotification('error', `Failed to update configuration: ${errorMessage}`);
    } finally {
      setUpdatingConfig(false);
    }
  };

  const handleCancelConfig = () => {
    if (group) {
      setMaskValue(group.mask || '');
      setInterfacesValue(group.interfaces || '');
    }
    setEditingConfig(false);
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
      setNewFollowDnsDomain('');

      // Small delay to ensure database transaction is committed
      await new Promise(resolve => setTimeout(resolve, 100));

      // Reload domains with type information
      await loadGroupDomains();

      // Also reload group data for statistics
      const updatedGroups = await apiService.getDomainGroups();
      const updatedGroup = updatedGroups.find(g => g.id === group.id);
      
      if (updatedGroup) {
        setGroup(updatedGroup);
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
            total_routes: 0,
            synced_routes: 0,
            pending_routes: 0,
          },
        };
        setGroup(convertedGroup);
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

  const handleDeleteDomain = async (domain: string, type: 'regular' | 'follow_dns' = 'follow_dns') => {
    if (!group) return;

    try {
      setDeletingDomain(domain);
      setError(null);

      await apiService.deleteDomainFromGroup(group.id, domain, type);
      showNotification('success', `Domain "${domain}" deleted successfully!`);

      // Reload domains with type information
      await loadGroupDomains();

      // Also reload group data for statistics
      const updatedGroups = await apiService.getDomainGroups();
      const updatedGroup = updatedGroups.find(g => g.id === group.id);
      
      if (updatedGroup) {
        setGroup(updatedGroup);
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
            total_routes: 0,
            synced_routes: 0,
            pending_routes: 0,
          },
        };
        setGroup(convertedGroup);
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

  const handleDeleteGroupRoutes = async () => {
    if (!groupName) return;

    setShowDeleteRoutesModal(false);
    setDeletingRoutes(true);

    try {
      const result = await apiService.deleteGroupRouterRoutes(groupName);
      showNotification('success', result.message || `Successfully deleted ${result.deleted_count || 0} routes for group "${groupName}"`);
      await loadRouterRoutes();
    } catch (err: any) {
      console.error('Error deleting group routes:', err);
      const errorMessage = err.response?.data?.error || err.message;
      setError(`Failed to delete group routes: ${errorMessage}`);
      showNotification('error', `Failed to delete group routes: ${errorMessage}`);
    } finally {
      setDeletingRoutes(false);
    }
  };

  const getDomainsList = () => {
    // Use domains with type information if available (preferred method)
    if (domainsWithTypes.length > 0) {
      return {
        followDns: domainsWithTypes.filter(d => d.type === 'follow_dns').map(d => d.domain)
      };
    }

    // Fallback to parsing from group.domains structure
    if (!group || !group.domains) return { followDns: [] };

    if (Array.isArray(group.domains)) {
      // Legacy format - treat as follow_dns
      return { followDns: group.domains };
    }

    if (typeof group.domains === 'object') {
      return {
        followDns: group.domains.follow_dns || []
      };
    }

    return { followDns: [] };
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
                variant="danger"
                onClick={handleDeleteClick}
                disabled={deleting || renaming || editingGroupName || editingConfig || updatingConfig}
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
        <Col>
          <Card className="h-100">
            <Card.Header>
              <h6 className="mb-0">
                <i className="fas fa-cog me-2"></i>
                Configuration
              </h6>
            </Card.Header>
            <Card.Body>
              <Row className="g-3">
                <Col md={6} lg={3}>
                  <div className="p-3 border rounded h-100 d-flex flex-column" style={{ minHeight: '120px' }}>
                    <div className="d-flex justify-content-between align-items-start mb-2">
                      <div className="small text-muted fw-semibold text-uppercase" style={{ fontSize: '0.75rem', letterSpacing: '0.5px' }}>
                        Network Mask
                      </div>
                      {!editingConfig && (
                        <Button
                          variant="link"
                          size="sm"
                          className="p-0"
                          onClick={() => setEditingConfig(true)}
                          title="Edit network mask"
                          style={{ fontSize: '0.75rem', lineHeight: '1' }}
                        >
                          <i className="fas fa-edit"></i>
                        </Button>
                      )}
                    </div>
                    <div className="mt-auto">
                      {editingConfig ? (
                        <Form.Control
                          type="text"
                          value={maskValue}
                          onChange={(e) => setMaskValue(e.target.value)}
                          placeholder="e.g., 32 or 255.255.255.0"
                          size="sm"
                        />
                      ) : (
                        group.mask ? (
                          <div className="fw-semibold text-primary" style={{ fontSize: '1.1rem' }}>
                            <code className="bg-light px-2 py-1 rounded">{group.mask}</code>
                          </div>
                        ) : (
                          <div className="text-muted fst-italic" style={{ fontSize: '0.9rem' }}>Not set</div>
                        )
                      )}
                    </div>
                  </div>
                </Col>

                <Col md={6} lg={3}>
                  <div className="p-3 border rounded h-100 d-flex flex-column" style={{ minHeight: '120px' }}>
                    <div className="d-flex justify-content-between align-items-start mb-2">
                      <div className="small text-muted fw-semibold text-uppercase" style={{ fontSize: '0.75rem', letterSpacing: '0.5px' }}>
                        Interface
                      </div>
                      {!editingConfig && (
                        <Button
                          variant="link"
                          size="sm"
                          className="p-0"
                          onClick={() => setEditingConfig(true)}
                          title="Edit interface"
                          style={{ fontSize: '0.75rem', lineHeight: '1' }}
                        >
                          <i className="fas fa-edit"></i>
                        </Button>
                      )}
                    </div>
                    <div className="mt-auto">
                      {editingConfig ? (
                        <Form.Select
                          value={interfacesValue}
                          onChange={(e) => setInterfacesValue(e.target.value)}
                          size="sm"
                          disabled={loadingInterfaces}
                        >
                          <option value="">Select interface...</option>
                          {routerInterfaces.map((iface) => (
                            <option key={iface.id} value={iface.id}>
                              {iface.description || iface.name || iface.id}
                            </option>
                          ))}
                          {interfacesValue && !routerInterfaces.some(iface => iface.id === interfacesValue) && (
                            <option value={interfacesValue}>{interfacesValue} (custom)</option>
                          )}
                        </Form.Select>
                      ) : (
                        group.interfaces ? (() => {
                          // Handle comma-separated interfaces
                          const interfaceIds = group.interfaces.split(',').map(id => id.trim());
                          const displayNames = interfaceIds.map(id => {
                            const interfaceData = routerInterfaces.find(iface => iface.id === id);
                            return interfaceData 
                              ? (interfaceData.description || interfaceData.name || interfaceData.id)
                              : id;
                          });
                          return (
                            <div className="fw-semibold" style={{ fontSize: '1rem' }}>
                              <Badge bg="info" className="px-2 py-1">{displayNames.join(', ')}</Badge>
                            </div>
                          );
                        })() : (
                          <div className="text-muted fst-italic" style={{ fontSize: '0.9rem' }}>Not set</div>
                        )
                      )}
                    </div>
                  </div>
                </Col>

                <Col md={6} lg={3}>
                  <div className="p-3 border rounded h-100 d-flex flex-column" style={{ minHeight: '120px' }}>
                    <div className="small text-muted fw-semibold text-uppercase mb-2" style={{ fontSize: '0.75rem', letterSpacing: '0.5px' }}>
                      Created
                    </div>
                    <div className="mt-auto d-flex align-items-center">
                      <i className="fas fa-calendar-plus me-2 text-success"></i>
                      <div className="fw-semibold text-dark" style={{ fontSize: '0.95rem' }}>
                        {formatDate(group.created_at)}
                      </div>
                    </div>
                  </div>
                </Col>

                <Col md={6} lg={3}>
                  <div className="p-3 border rounded h-100 d-flex flex-column" style={{ minHeight: '120px' }}>
                    <div className="small text-muted fw-semibold text-uppercase mb-2" style={{ fontSize: '0.75rem', letterSpacing: '0.5px' }}>
                      Last Updated
                    </div>
                    <div className="mt-auto d-flex align-items-center">
                      <i className="fas fa-clock me-2 text-warning"></i>
                      <div className="fw-semibold text-dark" style={{ fontSize: '0.95rem' }}>
                        {formatDate(group.updated_at)}
                      </div>
                    </div>
                  </div>
                </Col>

                <Col md={6} lg={3}>
                  <div className="p-3 border rounded bg-primary bg-opacity-10 h-100 d-flex flex-column justify-content-center" style={{ minHeight: '120px' }}>
                    <div className="text-center">
                      <div className="small text-muted fw-semibold text-uppercase mb-2" style={{ fontSize: '0.75rem', letterSpacing: '0.5px' }}>
                        Total Domains
                      </div>
                      <div className="h2 mb-0 text-primary fw-bold">{group.statistics.total_domains}</div>
                    </div>
                  </div>
                </Col>

                <Col md={6} lg={3}>
                  <div className="p-3 border rounded bg-info bg-opacity-10 h-100 d-flex flex-column justify-content-center" style={{ minHeight: '120px' }}>
                    <div className="text-center">
                      <div className="small text-muted fw-semibold text-uppercase mb-2" style={{ fontSize: '0.75rem', letterSpacing: '0.5px' }}>
                        IP Routes in Router
                      </div>
                      {routerRoutesLoading ? (
                        <div className="d-flex justify-content-center">
                          <div className="loading-spinner"></div>
                        </div>
                      ) : routerRoutesError ? (
                        <div className="text-muted small">Error</div>
                      ) : (
                        <div className="h2 mb-0 text-info fw-bold">{routerRoutes.length}</div>
                      )}
                    </div>
                  </div>
                </Col>
              </Row>

              {editingConfig && (
                <Row className="mt-3">
                  <Col>
                    <div className="d-flex gap-2">
                      <Button
                        variant="success"
                        size="sm"
                        onClick={handleSaveConfig}
                        disabled={updatingConfig}
                      >
                        {updatingConfig ? (
                          <>
                            <div className="loading-spinner me-1"></div>
                            Saving...
                          </>
                        ) : (
                          <>
                            <i className="fas fa-check me-1"></i>
                            Save
                          </>
                        )}
                      </Button>
                      <Button
                        variant="secondary"
                        size="sm"
                        onClick={handleCancelConfig}
                        disabled={updatingConfig}
                      >
                        Cancel
                      </Button>
                    </div>
                  </Col>
                </Row>
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
                <div>
                  <Button
                    variant="outline-danger"
                    size="sm"
                    onClick={() => setShowDeleteRoutesModal(true)}
                    disabled={routerRoutesLoading || deletingRoutes || routerRoutes.length === 0}
                    className="me-2"
                  >
                    {deletingRoutes ? (
                      <>
                        <div className="loading-spinner me-1"></div>
                        Deleting...
                      </>
                    ) : (
                      <>
                        <i className="fas fa-trash-alt me-1"></i>
                        Delete All Routes
                      </>
                    )}
                  </Button>
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
                        <th>Comment</th>
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

      <ConfirmModal
        show={showDeleteRoutesModal}
        title="Delete Group Routes from Router"
        message={`Are you sure you want to delete all ${routerRoutes.length} routes for group "${groupName}" from the router? This will remove all routes with [auto:${groupName}] comment from the Keenetic router.`}
        confirmText="Delete All"
        cancelText="Cancel"
        variant="danger"
        onConfirm={handleDeleteGroupRoutes}
        onCancel={() => setShowDeleteRoutesModal(false)}
      />
    </>
  );
};

export default GroupDetails;
