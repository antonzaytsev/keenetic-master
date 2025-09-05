import React, { useState, useEffect, useCallback } from 'react';
import { Card, Row, Col, Form, Button, Alert, Badge } from 'react-bootstrap';
import { Link } from 'react-router-dom';
import { apiService, DomainGroup } from '../services/api';

const DomainGroups: React.FC = () => {
  const [domainGroups, setDomainGroups] = useState<DomainGroup[]>([]);
  const [filteredGroups, setFilteredGroups] = useState<DomainGroup[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');

  const loadDomainGroups = useCallback(async () => {
    try {
      setLoading(true);
      console.log('Loading domain groups...');
      const groups = await apiService.getDomainGroups();
      console.log('Received domain groups:', groups);
      // Ensure groups is always an array
      const safeGroups = Array.isArray(groups) ? groups : [];
      console.log('Safe groups:', safeGroups);
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

  const renderDomainsList = (domains: any) => {
    let domainsList: string[] = [];
    
    if (Array.isArray(domains)) {
      domainsList = domains;
    } else if (domains && domains.domains) {
      domainsList = domains.domains;
    }

    if (!domainsList || domainsList.length === 0) {
      return <p className="text-muted mb-0">No domains configured</p>;
    }

    return (
      <div className="domain-list">
        <h6><i className="fas fa-samples me-2"></i>Sample Domains</h6>
        {domainsList.slice(0, 3).map((domain, index) => (
          <span key={index} className="domain-item">
            <i className="fas fa-globe fa-xs me-1"></i>
            {domain}
          </span>
        ))}
        {domainsList.length > 3 && (
          <span className="domain-item">
            <i className="fas fa-ellipsis-h"></i>
            +{domainsList.length - 3} more
          </span>
        )}
      </div>
    );
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
          {(Array.isArray(filteredGroups) ? filteredGroups : []).map((group) => (
            <Col key={group.id} md={6} lg={4} className="mb-4">
              <Card className="domain-group h-100">
                <Card.Header>
                  <h5 className="card-title mb-0">
                    <i className="fas fa-layer-group me-2"></i>
                    {group.name}
                  </h5>
                </Card.Header>
                <Card.Body>
                  {/* Statistics Row */}
                  <Row className="mb-3">
                    <Col xs={6}>
                      <div className="text-center">
                        <div className="h5 mb-0 text-primary">{group.statistics.total_domains}</div>
                        <small className="text-muted">Domains</small>
                      </div>
                    </Col>
                    <Col xs={6}>
                      <div className="text-center">
                        <div className="h5 mb-0 text-info">{group.statistics.total_routes}</div>
                        <small className="text-muted">IP Routes</small>
                      </div>
                    </Col>
                  </Row>

                  {/* Settings Section */}
                  {(group.mask || group.interfaces) && (
                    <div className="settings-section mb-3">
                      <h6><i className="fas fa-cog me-2"></i>Settings</h6>
                      {group.mask && (
                        <div><small className="text-muted">Mask: <code>{group.mask}</code></small></div>
                      )}
                      {group.interfaces && (
                        <div><small className="text-muted">Interfaces: <Badge bg="info">{group.interfaces}</Badge></small></div>
                      )}
                    </div>
                  )}

                  {/* Sync Status Section */}
                  {group.statistics.total_routes > 0 && (
                    <div className="settings-section mb-3">
                      <h6><i className="fas fa-sync me-2"></i>Sync Status</h6>
                      <div className="d-flex justify-content-between">
                        <small className="text-success">
                          <i className="fas fa-check me-1"></i>
                          {group.statistics.synced_routes} synced
                        </small>
                        {group.statistics.pending_routes > 0 && (
                          <small className="text-warning">
                            <i className="fas fa-clock me-1"></i>
                            {group.statistics.pending_routes} pending
                          </small>
                        )}
                      </div>
                    </div>
                  )}

                  {/* Domain Types */}
                  {group.statistics.total_domains > 0 && (
                    <div className="mb-3">
                      <div className="d-flex justify-content-between align-items-center mb-2">
                        <h6><i className="fas fa-list me-2"></i>Domain Types</h6>
                        <Link 
                          to={`/ip-addresses?group_id=${group.id}`}
                          className="btn btn-sm btn-outline-info"
                        >
                          <i className="fas fa-network-wired me-1"></i>
                          View Routes
                        </Link>
                      </div>
                      
                      {group.statistics.regular_domains > 0 && (
                        <div className="d-flex justify-content-between">
                          <small className="text-muted">
                            <i className="fas fa-globe me-1"></i>Regular
                          </small>
                          <Badge bg="primary">{group.statistics.regular_domains}</Badge>
                        </div>
                      )}
                      
                      {group.statistics.follow_dns_domains > 0 && (
                        <div className="d-flex justify-content-between">
                          <small className="text-muted">
                            <i className="fas fa-eye me-1"></i>DNS Monitoring
                          </small>
                          <Badge bg="success">{group.statistics.follow_dns_domains}</Badge>
                        </div>
                      )}
                    </div>
                  )}

                  {/* Sample Domains */}
                  {renderDomainsList(group.domains)}

                  {/* Last Updated */}
                  {group.statistics.last_updated && (
                    <div className="mt-2">
                      <small className="text-muted">
                        <i className="fas fa-clock me-1"></i>
                        Updated {new Date(group.statistics.last_updated).toLocaleDateString()} {new Date(group.statistics.last_updated).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}
                      </small>
                    </div>
                  )}
                </Card.Body>
                <Card.Footer>
                  <div className="btn-group w-100">
                    <Button variant="outline-primary" size="sm" disabled>
                      <i className="fas fa-edit me-1"></i>
                      Edit
                    </Button>
                    <Button 
                      variant="outline-danger" 
                      size="sm"
                      onClick={() => handleDeleteGroup(group.name)}
                    >
                      <i className="fas fa-trash me-1"></i>
                      Delete
                    </Button>
                  </div>
                </Card.Footer>
              </Card>
            </Col>
          ))}
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
