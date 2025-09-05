import React, { useState, useEffect, useCallback } from 'react';
import { Card, Row, Col, Form, Button, Alert, Badge, Table } from 'react-bootstrap';
import { Link, useNavigate } from 'react-router-dom';
import { apiService, DomainGroup } from '../services/api';

const DomainGroups: React.FC = () => {
  const navigate = useNavigate();
  const [domainGroups, setDomainGroups] = useState<DomainGroup[]>([]);
  const [filteredGroups, setFilteredGroups] = useState<DomainGroup[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');

  const loadDomainGroups = useCallback(async () => {
    try {
      setLoading(true);
      const groups = await apiService.getDomainGroups();
      const safeGroups = Array.isArray(groups) ? groups : [];
      setDomainGroups(safeGroups);
      setFilteredGroups(safeGroups);
      setError(null);
    } catch (err) {
      console.error('Failed to load domain groups:', err);
      setError(`Failed to load domain groups: ${err}`);
      // Reset to empty arrays on error
      setDomainGroups([]);
      setFilteredGroups([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadDomainGroups();

    // Auto-refresh every 30 seconds
    const interval = setInterval(() => {
      if (!searchTerm.trim()) {
        loadDomainGroups();
      }
    }, 30000);

    return () => clearInterval(interval);
  }, [loadDomainGroups, searchTerm]);

  useEffect(() => {
    // Ensure domainGroups is always an array before filtering
    const safeGroups = Array.isArray(domainGroups) ? domainGroups : [];
    const filtered = safeGroups.filter(group =>
      group.name.toLowerCase().includes(searchTerm.toLowerCase())
    );
    setFilteredGroups(filtered);
  }, [searchTerm, domainGroups]);

  const handleDeleteGroup = async (name: string) => {
    if (!window.confirm(`Are you sure you want to delete the domain group "${name}"?`)) {
      return;
    }

    try {
      await apiService.deleteDomainGroup(name);
      await loadDomainGroups();
    } catch (err) {
      setError(`Failed to delete domain group: ${err}`);
    }
  };

  const clearSearch = () => {
    setSearchTerm('');
  };


  if (loading) {
    return (
      <div className="text-center py-5">
        <div className="loading-spinner me-2"></div>
        Loading domain groups...
      </div>
    );
  }

  return (
    <div className="fade-in">
      <Row>
        <Col>
          <div className="d-flex justify-content-between align-items-center mb-4">
            <h1>
              <i className="fas fa-globe me-2"></i>
              Domain Groups
            </h1>
            <Button 
              variant="primary" 
              onClick={() => navigate('/groups/add')}
            >
              <i className="fas fa-plus me-1"></i>
              Add Group
            </Button>
          </div>
        </Col>
      </Row>

      {error && (
        <Alert variant="danger" dismissible onClose={() => setError(null)}>
          {error}
        </Alert>
      )}

      {domainGroups.length > 0 && (
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
                        placeholder="Search domain groups..."
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                      />
                    </div>
                  </Col>
                  <Col md={6} className="mt-2 mt-md-0">
                    <div className="d-flex justify-content-md-end align-items-center">
                      <small className="text-muted me-3">
                        {filteredGroups.length} of {domainGroups.length} groups
                      </small>
                      <Button variant="outline-secondary" size="sm" onClick={clearSearch}>
                        <i className="fas fa-times me-1"></i>
                        Clear
                      </Button>
                    </div>
                  </Col>
                </Row>
              </Card.Body>
            </Card>
          </Col>
        </Row>
      )}

      {domainGroups.length === 0 ? (
        <Row>
          <Col>
            <Card>
              <Card.Body className="text-center py-5">
                <i className="fas fa-inbox fa-3x text-muted mb-3"></i>
                <h5 className="text-muted">No domain groups found</h5>
                <p className="text-muted">Create your first domain group to get started</p>
              </Card.Body>
            </Card>
          </Col>
        </Row>
      ) : (
        <Row>
          <Col>
            <Card>
              <Card.Header>
                <h6 className="mb-0">
                  <i className="fas fa-list me-2"></i>
                  Domain Groups
                </h6>
              </Card.Header>
              <Card.Body className="p-0">
                <div className="table-responsive">
                  <Table hover className="mb-0">
                    <thead className="table-light">
                      <tr>
                        <th>Group Name</th>
                        <th>Domains</th>
                        <th>DNS Monitoring</th>
                        <th>IP Routes</th>
                        <th>Sync Status</th>
                        <th>Interface</th>
                        <th>Last Updated</th>
                        <th>Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      {(Array.isArray(filteredGroups) ? filteredGroups : []).map((group) => (
                        <tr key={group.id}>
                          <td>
                            <Link
                              to={`/groups/${group.name}`}
                              className="text-decoration-none fw-bold"
                            >
                              <i className="fas fa-layer-group me-2 text-primary"></i>
                              {group.name}
                            </Link>
                            {group.mask && (
                              <div>
                                <small className="text-muted">Mask: <code>{group.mask}</code></small>
                              </div>
                            )}
                          </td>
                          <td>
                            <Badge bg="primary" className="me-1">
                              {group.statistics.regular_domains}
                            </Badge>
                            <small className="text-muted">regular</small>
                          </td>
                          <td>
                            {group.statistics.follow_dns_domains > 0 ? (
                              <>
                                <Badge bg="success" className="me-1">
                                  {group.statistics.follow_dns_domains}
                                </Badge>
                                <small className="text-muted">monitored</small>
                              </>
                            ) : (
                              <span className="text-muted">-</span>
                            )}
                          </td>
                          <td>
                            <Link
                              to={`/ip-addresses?group_id=${group.id}`}
                              className="text-decoration-none"
                            >
                              <Badge bg="info" className="me-1">
                                {group.statistics.total_routes}
                              </Badge>
                              <small className="text-muted">routes</small>
                            </Link>
                          </td>
                          <td>
                            {group.statistics.total_routes > 0 ? (
                              <div>
                                <Badge bg="success" className="me-1">
                                  {group.statistics.synced_routes}
                                </Badge>
                                <small className="text-success">synced</small>
                                {group.statistics.pending_routes > 0 && (
                                  <>
                                    <br />
                                    <Badge bg="warning" className="me-1">
                                      {group.statistics.pending_routes}
                                    </Badge>
                                    <small className="text-warning">pending</small>
                                  </>
                                )}
                              </div>
                            ) : (
                              <span className="text-muted">-</span>
                            )}
                          </td>
                          <td>
                            {group.interfaces ? (
                              <Badge bg="info">{group.interfaces}</Badge>
                            ) : (
                              <span className="text-muted">-</span>
                            )}
                          </td>
                          <td>
                            {group.statistics.last_updated ? (
                              <small className="text-muted">
                                {new Date(group.statistics.last_updated).toLocaleDateString()}
                                <br />
                                {new Date(group.statistics.last_updated).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}
                              </small>
                            ) : (
                              <span className="text-muted">-</span>
                            )}
                          </td>
                          <td>
                            <div className="btn-group">
                              <Link
                                to={`/groups/${group.name}`}
                                className="btn btn-outline-primary btn-sm"
                                title="View Details"
                              >
                                <i className="fas fa-eye"></i>
                              </Link>
                              <Link
                                to={`/groups/${group.name}/edit`}
                                className="btn btn-outline-secondary btn-sm"
                                title="Edit Group"
                              >
                                <i className="fas fa-edit"></i>
                              </Link>
                              <Button
                                variant="outline-danger"
                                size="sm"
                                onClick={() => handleDeleteGroup(group.name)}
                                title="Delete Group"
                              >
                                <i className="fas fa-trash"></i>
                              </Button>
                            </div>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </Table>
                </div>
              </Card.Body>
            </Card>
          </Col>
        </Row>
      )}

      {filteredGroups.length === 0 && domainGroups.length > 0 && searchTerm && (
        <Row>
          <Col>
            <Card>
              <Card.Body className="text-center py-5">
                <i className="fas fa-search fa-3x text-muted mb-3"></i>
                <h5 className="text-muted">No matching domain groups found</h5>
                <p className="text-muted">Try adjusting your search terms</p>
                <Button variant="outline-primary" onClick={clearSearch}>
                  <i className="fas fa-times me-2"></i>
                  Clear Search
                </Button>
              </Card.Body>
            </Card>
          </Col>
        </Row>
      )}
    </div>
  );
};

export default DomainGroups;
