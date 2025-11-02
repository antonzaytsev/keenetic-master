import React, { useState, useEffect, useCallback } from 'react';
import { Card, Row, Col, Form, Button, Alert, Badge, Table } from 'react-bootstrap';
import { apiService } from '../services/api';

interface RouterRoute {
  id: number;
  network?: string;
  mask?: string;
  interface?: string;
  gateway?: string;
  flags?: string;
  table?: string;
  dev?: string;
  src?: string;
  description?: string;
}

const RouterRoutes: React.FC = () => {
  const [routes, setRoutes] = useState<RouterRoute[]>([]);
  const [filteredRoutes, setFilteredRoutes] = useState<RouterRoute[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  
  // Filter states
  const [networkSearch, setNetworkSearch] = useState('');
  const [interfaceFilter, setInterfaceFilter] = useState('');
  
  // Available filter options
  const [availableInterfaces, setAvailableInterfaces] = useState<string[]>([]);

  const loadRouterRoutes = useCallback(async () => {
    try {
      setLoading(true);
      const result = await apiService.getAllRouterRoutes();
      
      if (result.success) {
        const routeData = result.routes || [];
        setRoutes(routeData);
        
        // Extract unique values for filter options
        const interfaces: string[] = [];
        
        routeData.forEach((r: RouterRoute) => {
          if (r.interface && !interfaces.includes(r.interface)) {
            interfaces.push(r.interface);
          }
        });
        
        interfaces.sort();
        
        setAvailableInterfaces(interfaces);
        setError(null);
      } else {
        setError('Failed to load router routes');
        setRoutes([]);
      }
    } catch (err: any) {
      console.error('Failed to load router routes:', err);
      setError(`Failed to load router routes: ${err.response?.data?.error || err.message}`);
      setRoutes([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadRouterRoutes();
    
    // Auto-refresh every 60 seconds (router data changes less frequently)
    const interval = setInterval(() => {
      if (!networkSearch.trim() && !interfaceFilter) {
        loadRouterRoutes();
      }
    }, 60000);

    return () => clearInterval(interval);
  }, [loadRouterRoutes, networkSearch, interfaceFilter]);

  useEffect(() => {
    let filtered = routes;

    // Apply network search filter
    if (networkSearch.trim()) {
      filtered = filtered.filter(route =>
        route.network?.toLowerCase().includes(networkSearch.toLowerCase()) ||
        route.gateway?.toLowerCase().includes(networkSearch.toLowerCase())
      );
    }

    // Apply interface filter
    if (interfaceFilter) {
      filtered = filtered.filter(route => route.interface === interfaceFilter);
    }

    setFilteredRoutes(filtered);
  }, [networkSearch, interfaceFilter, routes]);

  const clearFilters = () => {
    setNetworkSearch('');
    setInterfaceFilter('');
  };

  if (loading) {
    return (
      <div className="text-center py-5">
        <div className="loading-spinner me-2"></div>
        Loading router routes...
      </div>
    );
  }

  return (
    <>
      <Row>
        <Col>
          <div className="d-flex justify-content-between align-items-center mb-4">
            <h1>
              <i className="fas fa-router me-2"></i>
              Router Routes
            </h1>
            <div className="d-flex align-items-center">
              <div className="me-3">
                <small className="text-muted">
                  Total: <Badge bg="primary">{routes.length}</Badge>{' '}
                  Filtered: <Badge bg="info">{filteredRoutes.length}</Badge>
                </small>
              </div>
              <Button variant="outline-primary" size="sm" onClick={loadRouterRoutes} disabled={loading}>
                <i className="fas fa-refresh me-1"></i>
                Refresh
              </Button>
            </div>
          </div>
        </Col>
      </Row>

      {error && (
        <Alert variant="danger" dismissible onClose={() => setError(null)}>
          <i className="fas fa-exclamation-triangle me-2"></i>
          {error}
        </Alert>
      )}

      {/* Filter Section */}
      {routes.length > 0 && (
        <Row className="mb-4">
          <Col>
            <Card>
              <Card.Body>
                <Row className="align-items-center">
                  <Col md={6}>
                    <div className="input-group">
                      <span className="input-group-text">
                        <i className="fas fa-search"></i>
                      </span>
                      <Form.Control
                        type="text"
                        placeholder="Search networks or gateways..."
                        value={networkSearch}
                        onChange={(e) => setNetworkSearch(e.target.value)}
                      />
                    </div>
                  </Col>
                  <Col md={4} className="mt-2 mt-md-0">
                    <Form.Select
                      value={interfaceFilter}
                      onChange={(e) => setInterfaceFilter(e.target.value)}
                    >
                      <option value="">All Interfaces</option>
                      {availableInterfaces.map(iface => (
                        <option key={iface} value={iface}>
                          {iface}
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

      {/* Routes Table */}
      {routes.length === 0 ? (
        <Row>
          <Col>
            <Card>
              <Card.Body className="text-center py-5">
                <i className="fas fa-router fa-3x text-muted mb-3"></i>
                <h5 className="text-muted">No router routes found</h5>
                <p className="text-muted">Unable to retrieve routes from the router or router is unreachable</p>
                <Button variant="outline-primary" onClick={loadRouterRoutes}>
                  <i className="fas fa-refresh me-1"></i>
                  Try Again
                </Button>
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
                    Router Routes Table
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
                        <th>Gateway</th>
                        <th>Description</th>
                      </tr>
                    </thead>
                    <tbody>
                      {filteredRoutes.length === 0 && (networkSearch || interfaceFilter) ? (
                        <tr>
                          <td colSpan={5} className="text-center py-4">
                            <i className="fas fa-search fa-2x text-muted mb-3"></i>
                            <h6 className="text-muted">No matching routes found</h6>
                            <p className="text-muted mb-0">Try adjusting your search terms or filters</p>
                          </td>
                        </tr>
                      ) : (
                        filteredRoutes.map((route) => (
                          <tr key={route.id}>
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
                              {route.gateway ? (
                                <code className="text-secondary">{route.gateway}</code>
                              ) : (
                                <span className="text-muted">-</span>
                              )}
                            </td>
                            <td>
                              <span className="text-muted">{route.description || '-'}</span>
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
    </>
  );
};

export default RouterRoutes;
