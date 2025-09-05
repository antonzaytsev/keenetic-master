import React, { useState, useEffect } from 'react';
import { Card, Row, Col, Alert, Badge, Table, Button, Breadcrumb } from 'react-bootstrap';
import { Link, useParams } from 'react-router-dom';
import { apiService, DomainGroup, Route } from '../services/api';

const GroupDetails: React.FC = () => {
  const { groupName } = useParams<{ groupName: string }>();
  const [group, setGroup] = useState<DomainGroup | null>(null);
  const [routes, setRoutes] = useState<Route[]>([]);
  const [routerRoutes, setRouterRoutes] = useState<any[]>([]);
  const [routerRoutesLoading, setRouterRoutesLoading] = useState(false);
  const [routerRoutesError, setRouterRoutesError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [generating, setGenerating] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);

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
    }
  }, [group]);

  const formatDate = (dateString?: string) => {
    if (!dateString) return 'Never';
    const date = new Date(dateString);
    return date.toLocaleDateString() + ' ' + date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
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
      setSuccessMessage(null);
      
      const result = await apiService.generateIPs(groupName);
      
      if (result.success) {
        setSuccessMessage(`${result.message} (Added: ${result.statistics.added}, Deleted: ${result.statistics.deleted}, Total: ${result.statistics.total}). Refreshing route data...`);
        
        // Reload database routes immediately
        const updatedRoutes = await apiService.getRoutes({ group_id: groupName });
        
        // Small delay before refreshing router routes to allow time for routes to appear
        setTimeout(async () => {
          setSuccessMessage(`${result.message} (Added: ${result.statistics.added}, Deleted: ${result.statistics.deleted}, Total: ${result.statistics.total}). Database routes updated, refreshing router routes...`);
          await loadRouterRoutes();
          setSuccessMessage(`${result.message} (Added: ${result.statistics.added}, Deleted: ${result.statistics.deleted}, Total: ${result.statistics.total}). All route data updated!`);
        }, 1000);
        
        setRoutes(updatedRoutes);
        
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
      setError(`Failed to generate IP addresses: ${err.response?.data?.error || err.message}`);
    } finally {
      setGenerating(false);
    }
  };

  const handleSyncToRouter = async () => {
    if (!groupName) return;
    
    try {
      setSyncing(true);
      setError(null);
      setSuccessMessage(null);
      
      const result = await apiService.syncToRouter(groupName);
      
      if (result.success) {
        setSuccessMessage(`${result.message} Refreshing route data...`);
        
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
        setTimeout(async () => {
          setSuccessMessage(`${result.message} Refreshing router routes...`);
          await loadRouterRoutes();
          setSuccessMessage(`${result.message} All route data updated!`);
        }, 500);
      }
    } catch (err: any) {
      console.error('Error syncing to router:', err);
      setError(`Failed to sync to router: ${err.response?.data?.error || err.message}`);
    } finally {
      setSyncing(false);
    }
  };

  const getDomainsList = () => {
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
      <div className="fade-in">
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
      </div>
    );
  }

  const domains = getDomainsList();

  if (!group) {
    return null; // This shouldn't happen due to the check above, but TypeScript needs it
  }

  return (
    <div className="fade-in">
      <Breadcrumb>
        <Breadcrumb.Item linkAs={Link} linkProps={{ to: '/' }}>Domain Groups</Breadcrumb.Item>
        <Breadcrumb.Item active>{group.name}</Breadcrumb.Item>
      </Breadcrumb>

      <Row>
        <Col>
          <div className="d-flex justify-content-between align-items-center mb-4">
            <h1>
              <i className="fas fa-layer-group me-2"></i>
              {group.name}
            </h1>
            <div>
              <Link to="/" className="btn btn-outline-secondary me-2">
                <i className="fas fa-arrow-left me-1"></i>
                Back to Groups
              </Link>
              <Link 
                to={`/groups/${group.name}/edit`}
                className="btn btn-outline-primary me-2"
              >
                <i className="fas fa-edit me-1"></i>
                Edit Group
              </Link>
              <Button 
                variant="success"
                className="me-2"
                onClick={handleGenerateIPs}
                disabled={generating || syncing}
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
                disabled={generating || syncing || group.statistics.pending_routes === 0}
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
                className="btn btn-primary"
              >
                <i className="fas fa-network-wired me-1"></i>
                View All Routes
              </Link>
            </div>
          </div>
        </Col>
      </Row>

      {/* Success/Error Messages */}
      {successMessage && (
        <Alert variant="success" className="mb-4" dismissible onClose={() => setSuccessMessage(null)}>
          <i className="fas fa-check-circle me-2"></i>
          {successMessage}
        </Alert>
      )}
      
      {error && (
        <Alert variant="danger" className="mb-4" dismissible onClose={() => setError(null)}>
          <i className="fas fa-exclamation-triangle me-2"></i>
          {error}
        </Alert>
      )}

      {/* Group Information */}
      <Row className="mb-4">
        <Col md={6}>
          <Card>
            <Card.Header>
              <h6 className="mb-0">
                <i className="fas fa-info-circle me-2"></i>
                Group Information
              </h6>
            </Card.Header>
            <Card.Body>
              <Row className="mb-3">
                <Col sm={4}><strong>Name:</strong></Col>
                <Col sm={8}>{group.name}</Col>
              </Row>
              
              {group.mask && (
                <Row className="mb-3">
                  <Col sm={4}><strong>Mask:</strong></Col>
                  <Col sm={8}><code>{group.mask}</code></Col>
                </Row>
              )}
              
              {group.interfaces && (
                <Row className="mb-3">
                  <Col sm={4}><strong>Interface:</strong></Col>
                  <Col sm={8}><Badge bg="info">{group.interfaces}</Badge></Col>
                </Row>
              )}
              
              <Row className="mb-3">
                <Col sm={4}><strong>Created:</strong></Col>
                <Col sm={8}>{formatDate(group.created_at)}</Col>
              </Row>
              
              <Row>
                <Col sm={4}><strong>Last Updated:</strong></Col>
                <Col sm={8}>{formatDate(group.updated_at)}</Col>
              </Row>
            </Card.Body>
          </Card>
        </Col>
        
        <Col md={6}>
          <Card>
            <Card.Header>
              <h6 className="mb-0">
                <i className="fas fa-chart-bar me-2"></i>
                Statistics
              </h6>
            </Card.Header>
            <Card.Body>
              <Row className="text-center mb-3">
                <Col xs={6}>
                  <div className="h4 mb-1 text-primary">{group.statistics.total_domains}</div>
                  <div className="text-muted">Total Domains</div>
                </Col>
                <Col xs={6}>
                  <div className="h4 mb-1 text-info">{group.statistics.total_routes}</div>
                  <div className="text-muted">IP Routes</div>
                </Col>
              </Row>
              
              <Row className="text-center">
                <Col xs={4}>
                  <div className="h5 mb-1 text-success">{group.statistics.synced_routes}</div>
                  <div className="text-muted small">Synced</div>
                </Col>
                <Col xs={4}>
                  <div className="h5 mb-1 text-warning">{group.statistics.pending_routes}</div>
                  <div className="text-muted small">Pending</div>
                </Col>
                <Col xs={4}>
                  <div className="h5 mb-1 text-primary">{group.statistics.regular_domains}</div>
                  <div className="text-muted small">Regular</div>
                </Col>
              </Row>
              
              {group.statistics.follow_dns_domains > 0 && (
                <Row className="text-center mt-3">
                  <Col>
                    <div className="h5 mb-1 text-success">{group.statistics.follow_dns_domains}</div>
                    <div className="text-muted small">DNS Monitored</div>
                  </Col>
                </Row>
              )}
            </Card.Body>
          </Card>
        </Col>
      </Row>

      {/* Regular Domains */}
      {domains.regular.length > 0 && (
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
                <Row>
                  {domains.regular.map((domain: string, index: number) => (
                    <Col key={index} md={6} lg={4} className="mb-2">
                      <div className="domain-item">
                        <i className="fas fa-globe fa-xs me-2 text-primary"></i>
                        {domain}
                      </div>
                    </Col>
                  ))}
                </Row>
              </Card.Body>
            </Card>
          </Col>
        </Row>
      )}

      {/* DNS Follow Domains */}
      {domains.followDns.length > 0 && (
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
                <Row>
                  {domains.followDns.map((domain: string, index: number) => (
                    <Col key={index} md={6} lg={4} className="mb-2">
                      <div className="domain-item">
                        <i className="fas fa-eye fa-xs me-2 text-success"></i>
                        {domain}
                      </div>
                    </Col>
                  ))}
                </Row>
              </Card.Body>
            </Card>
          </Col>
        </Row>
      )}

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
    </div>
  );
};

export default GroupDetails;
