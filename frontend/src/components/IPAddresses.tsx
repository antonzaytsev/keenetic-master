import React, { useState, useEffect, useCallback } from 'react';
import { Card, Row, Col, Form, Button, Alert, Badge, Table } from 'react-bootstrap';
import { useSearchParams } from 'react-router-dom';
import { apiService, Route, DomainGroup } from '../services/api';

const IPAddresses: React.FC = () => {
  const [routes, setRoutes] = useState<Route[]>([]);
  const [filteredRoutes, setFilteredRoutes] = useState<Route[]>([]);
  const [domainGroups, setDomainGroups] = useState<DomainGroup[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [syncStatusFilter, setSyncStatusFilter] = useState('');
  const [groupFilter, setGroupFilter] = useState('');
  const [searchParams] = useSearchParams();

  const loadRoutes = useCallback(async () => {
    try {
      setLoading(true);
      const [routesData, groupsData] = await Promise.all([
        apiService.getRoutes(),
        apiService.getDomainGroups()
      ]);
      
      setRoutes(routesData);
      setDomainGroups(groupsData);
      setError(null);
    } catch (err) {
      setError(`Failed to load IP addresses: ${err}`);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadRoutes();
    
    // Check for URL parameters
    const groupId = searchParams.get('group_id');
    if (groupId) {
      setGroupFilter(groupId);
    }
    
    // Auto-refresh every 30 seconds
    const interval = setInterval(() => {
      if (!searchTerm.trim() && !syncStatusFilter && !groupFilter) {
        loadRoutes();
      }
    }, 30000);

    return () => clearInterval(interval);
  }, [loadRoutes, searchParams, searchTerm, syncStatusFilter, groupFilter]);

  useEffect(() => {
    let filtered = routes;

    // Apply search filter
    if (searchTerm.trim()) {
      filtered = filtered.filter(route =>
        route.network.toLowerCase().includes(searchTerm.toLowerCase())
      );
    }

    // Apply sync status filter
    if (syncStatusFilter) {
      filtered = filtered.filter(route => {
        if (syncStatusFilter === 'synced') return route.synced_to_router;
        if (syncStatusFilter === 'unsynced') return !route.synced_to_router;
        return true;
      });
    }

    // Apply group filter
    if (groupFilter) {
      const groupName = domainGroups.find(g => g.id.toString() === groupFilter)?.name;
      filtered = filtered.filter(route => route.group_name === groupName);
    }

    setFilteredRoutes(filtered);
  }, [searchTerm, syncStatusFilter, groupFilter, routes, domainGroups]);

  const clearFilters = () => {
    setSearchTerm('');
    setSyncStatusFilter('');
    setGroupFilter('');
  };

  const getRouteStats = () => {
    return {
      total: routes.length,
      synced: routes.filter(r => r.synced_to_router).length,
      unsynced: routes.filter(r => !r.synced_to_router).length
    };
  };

  const formatDate = (dateString?: string) => {
    if (!dateString) return 'Never';
    const date = new Date(dateString);
    return date.toLocaleDateString() + ' ' + date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
  };

  if (loading) {
    return (
      <div className="text-center py-5">
        <div className="loading-spinner me-2"></div>
        Loading IP addresses...
      </div>
    );
  }

  const stats = getRouteStats();

  return (
    <div className="fade-in">
      <Row>
        <Col>
          <div className="d-flex justify-content-between align-items-center mb-4">
            <h1>
              <i className="fas fa-network-wired me-2"></i>
              IP Address Routes
            </h1>
            <div className="d-flex align-items-center">
              <div className="me-3">
                <small className="text-muted">
                  Total: <Badge bg="primary">{stats.total}</Badge>{' '}
                  Synced: <Badge bg="success">{stats.synced}</Badge>{' '}
                  Unsynced: <Badge bg="warning">{stats.unsynced}</Badge>
                </small>
              </div>
            </div>
          </div>
        </Col>
      </Row>

      {error && (
        <Alert variant="danger" dismissible onClose={() => setError(null)}>
          {error}
        </Alert>
      )}

      {routes.length > 0 && (
        <Row className="mb-4">
          <Col>
            <Card>
              <Card.Body>
                <Row className="align-items-center">
                  <Col md={4}>
                    <div className="input-group">
                      <span className="input-group-text">
                        <i className="fas fa-search"></i>
                      </span>
                      <Form.Control
                        type="text"
                        placeholder="Search IP addresses..."
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                      />
                    </div>
                  </Col>
                  <Col md={3} className="mt-2 mt-md-0">
                    <Form.Select
                      value={syncStatusFilter}
                      onChange={(e) => setSyncStatusFilter(e.target.value)}
                    >
                      <option value="">All Sync Statuses</option>
                      <option value="synced">Synced to Router</option>
                      <option value="unsynced">Not Synced</option>
                    </Form.Select>
                  </Col>
                  <Col md={3} className="mt-2 mt-md-0">
                    <Form.Select
                      value={groupFilter}
                      onChange={(e) => setGroupFilter(e.target.value)}
                    >
                      <option value="">All Domain Groups</option>
                      {domainGroups.map(group => (
                        <option key={group.id} value={group.id}>
                          {group.name}
                        </option>
                      ))}
                    </Form.Select>
                  </Col>
                  <Col md={2} className="mt-2 mt-md-0">
                    <Button variant="outline-secondary" size="sm" className="w-100" onClick={clearFilters}>
                      <i className="fas fa-times me-1"></i>
                      Clear
                    </Button>
                  </Col>
                </Row>
              </Card.Body>
            </Card>
          </Col>
        </Row>
      )}

      {routes.length === 0 ? (
        <Row>
          <Col>
            <Card>
              <Card.Body className="text-center py-5">
                <i className="fas fa-network-wired fa-3x text-muted mb-3"></i>
                <h5 className="text-muted">No IP routes found</h5>
                <p className="text-muted">Routes will appear here once domains are resolved and compiled</p>
              </Card.Body>
            </Card>
          </Col>
        </Row>
      ) : (
        <Row>
          <Col>
            <Card>
              <Card.Header>
                <div className="d-flex justify-content-between align-items-center">
                  <h6 className="mb-0">
                    <i className="fas fa-list me-2"></i>
                    IP Address Routes
                  </h6>
                  <small className="text-muted">
                    {filteredRoutes.length} of {routes.length} routes
                  </small>
                </div>
              </Card.Header>
              <Card.Body className="p-0">
                <div className="table-responsive">
                  <Table hover className="mb-0">
                    <thead className="table-light">
                      <tr>
                        <th>Network</th>
                        <th>Mask</th>
                        <th>Interface</th>
                        <th>Domain Group</th>
                        <th>Sync Status</th>
                        <th>Last Sync</th>
                        <th>Comment</th>
                      </tr>
                    </thead>
                    <tbody>
                      {filteredRoutes.length === 0 && (searchTerm || syncStatusFilter || groupFilter) ? (
                        <tr>
                          <td colSpan={7} className="text-center py-4">
                            <i className="fas fa-search fa-2x text-muted mb-3"></i>
                            <h6 className="text-muted">No matching routes found</h6>
                            <p className="text-muted mb-0">Try adjusting your search terms or filters</p>
                          </td>
                        </tr>
                      ) : (
                        filteredRoutes.map((route) => (
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
                              {route.group_name ? (
                                <span className="text-decoration-none">
                                  <i className="fas fa-layer-group me-1"></i>
                                  {route.group_name}
                                </span>
                              ) : (
                                <span className="text-muted">No group</span>
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
                        ))
                      )}
                    </tbody>
                  </Table>
                </div>
              </Card.Body>
            </Card>
          </Col>
        </Row>
      )}
    </div>
  );
};

export default IPAddresses;
