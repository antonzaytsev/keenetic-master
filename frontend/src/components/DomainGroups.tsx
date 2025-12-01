import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { Card, Row, Col, Form, Button, Alert, Badge, Table } from 'react-bootstrap';
import { Link, useNavigate } from 'react-router-dom';
import { apiService, DomainGroup } from '../services/api';
import { useNotification } from '../contexts/NotificationContext';
import ConfirmModal from './ConfirmModal';

const DomainGroups: React.FC = () => {
  const navigate = useNavigate();
  const { showNotification } = useNotification();
  const [domainGroups, setDomainGroups] = useState<DomainGroup[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [groupToDelete, setGroupToDelete] = useState<string | null>(null);
  const searchInputRef = useRef<HTMLInputElement>(null);
  const searchTermRef = useRef<string>('');

  const loadDomainGroups = useCallback(async () => {
    try {
      setLoading(true);
      const groups = await apiService.getDomainGroups();
      const safeGroups = Array.isArray(groups) ? groups : [];
      setDomainGroups(safeGroups);
      setError(null);
    } catch (err) {
      console.error('Failed to load domain groups:', err);
      setError(`Failed to load domain groups: ${err}`);
      setDomainGroups([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    searchTermRef.current = searchTerm;
  }, [searchTerm]);

  useEffect(() => {
    loadDomainGroups();

    // Auto-refresh every 30 seconds
    const interval = setInterval(() => {
      if (!searchTermRef.current.trim()) {
        loadDomainGroups();
      }
    }, 30000);

    return () => clearInterval(interval);
  }, [loadDomainGroups]);

  const getAllDomainsFromGroup = useCallback((group: DomainGroup): string[] => {
    const domains: string[] = [];
    
    if (!group.domains) {
      return domains;
    }
    
    // If domains is a simple array
    if (Array.isArray(group.domains)) {
      domains.push(...group.domains);
    }
    // If domains is an object/hash
    else if (typeof group.domains === 'object') {
      // Regular domains
      if (Array.isArray(group.domains.domains)) {
        domains.push(...group.domains.domains);
      }
      // Follow DNS domains
      if (Array.isArray(group.domains.follow_dns)) {
        domains.push(...group.domains.follow_dns);
      }
    }
    
    return domains;
  }, []);

  const filteredGroups = useMemo(() => {
    const safeGroups = Array.isArray(domainGroups) ? domainGroups : [];
    if (!searchTerm.trim()) {
      return safeGroups;
    }
    
    const searchLower = searchTerm.toLowerCase();
    
    return safeGroups.filter(group => {
      // Search by group name
      if (group.name.toLowerCase().includes(searchLower)) {
        return true;
      }
      
      // Search by domains
      const allDomains = getAllDomainsFromGroup(group);
      return allDomains.some(domain => 
        domain.toLowerCase().includes(searchLower)
      );
    });
  }, [searchTerm, domainGroups, getAllDomainsFromGroup]);

  const handleSearchChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    setSearchTerm(e.target.value);
  }, []);

  const handleDeleteClick = (name: string) => {
    setGroupToDelete(name);
    setShowDeleteModal(true);
  };

  const handleDeleteConfirm = async () => {
    if (!groupToDelete) return;

    setShowDeleteModal(false);
    const nameToDelete = groupToDelete;
    setGroupToDelete(null);

    try {
      await apiService.deleteDomainGroup(nameToDelete);
      showNotification('success', `Domain group "${nameToDelete}" deleted successfully!`);
      await loadDomainGroups();
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      setError(`Failed to delete domain group: ${errorMessage}`);
      showNotification('error', `Failed to delete domain group: ${errorMessage}`);
    }
  };

  const handleDeleteCancel = () => {
    setShowDeleteModal(false);
    setGroupToDelete(null);
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
    <>
      <Row>
        <Col>
          <div className="page-header">
            <h1>Domain Groups</h1>
            <div className="page-header-actions">
              <Button 
                variant="primary" 
                onClick={() => navigate('/groups/add')}
              >
                <i className="fas fa-plus me-1"></i>
                Add Group
              </Button>
            </div>
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
                        ref={searchInputRef}
                        type="text"
                        placeholder="Search by group name or domain..."
                        value={searchTerm}
                        onChange={handleSearchChange}
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
                            {group.statistics.follow_dns_domains > 0 ? (
                              <>
                                <Badge bg="success" className="me-1">
                                  {group.statistics.follow_dns_domains}
                                </Badge>
                                <small className="text-muted">DNS monitored</small>
                              </>
                            ) : (
                              <span className="text-muted">-</span>
                            )}
                          </td>
                          <td>
                            <span className="text-muted">-</span>
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
                              <Button
                                variant="outline-danger"
                                size="sm"
                                onClick={() => handleDeleteClick(group.name)}
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

      <ConfirmModal
        show={showDeleteModal}
        title="Delete Domain Group"
        message={groupToDelete ? `Are you sure you want to delete the domain group "${groupToDelete}"?` : ''}
        confirmText="Delete"
        cancelText="Cancel"
        variant="danger"
        onConfirm={handleDeleteConfirm}
        onCancel={handleDeleteCancel}
      />
    </>
  );
};

export default DomainGroups;
