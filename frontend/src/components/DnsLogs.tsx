import React, { useState, useEffect, useCallback } from 'react';
import { Card, Row, Col, Form, Button, Alert, Badge, Table, Pagination } from 'react-bootstrap';
import { apiService, DnsLog, DnsLogsResponse, DnsLogsStatsResponse } from '../services/api';

const DnsLogs: React.FC = () => {
  const [logs, setLogs] = useState<DnsLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [stats, setStats] = useState<DnsLogsStatsResponse | null>(null);
  
  // Pagination states
  const [currentPage, setCurrentPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [totalCount, setTotalCount] = useState(0);
  const [perPage] = useState(50);
  
  // Filter states
  const [searchTerm, setSearchTerm] = useState('');
  const [actionFilter, setActionFilter] = useState('');
  const [groupFilter, setGroupFilter] = useState('');
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  
  // Available filter options
  const [availableActions, setAvailableActions] = useState<string[]>([]);
  const [availableGroups, setAvailableGroups] = useState<string[]>([]);

  const loadDnsLogs = useCallback(async (page: number = 1) => {
    try {
      setLoading(true);
      const params = {
        page,
        per_page: perPage,
        ...(searchTerm && { search: searchTerm }),
        ...(actionFilter && { action: actionFilter }),
        ...(groupFilter && { group_name: groupFilter }),
        ...(startDate && { start_date: startDate }),
        ...(endDate && { end_date: endDate })
      };
      
      const result: DnsLogsResponse = await apiService.getDnsLogs(params);
      
      setLogs(result.logs);
      setCurrentPage(result.pagination.page);
      setTotalPages(result.pagination.total_pages);
      setTotalCount(result.pagination.total_count);
      setError(null);
      
      // Update filter options with unique values from loaded logs
      const actions = Array.from(new Set(result.logs.map(log => log.action).filter(Boolean)));
      const groups = Array.from(new Set(result.logs.map(log => log.group_name).filter(Boolean)));
      
      setAvailableActions(actions.sort());
      setAvailableGroups(groups.sort());
      
    } catch (err: any) {
      console.error('Failed to load DNS logs:', err);
      setError(`Failed to load DNS logs: ${err.response?.data?.error || err.message}`);
      setLogs([]);
    } finally {
      setLoading(false);
    }
  }, [searchTerm, actionFilter, groupFilter, startDate, endDate, perPage]);

  const loadStats = useCallback(async () => {
    try {
      const statsResult = await apiService.getDnsLogsStats();
      setStats(statsResult);
    } catch (err: any) {
      console.error('Failed to load DNS logs stats:', err);
    }
  }, []);

  useEffect(() => {
    loadDnsLogs(1);
    loadStats();
    
    // Auto-refresh every 30 seconds
    const interval = setInterval(() => {
      if (currentPage === 1 && !searchTerm && !actionFilter && !groupFilter && !startDate && !endDate) {
        loadDnsLogs(1);
        loadStats();
      }
    }, 30000);

    return () => clearInterval(interval);
  }, [loadDnsLogs, loadStats, currentPage, searchTerm, actionFilter, groupFilter, startDate, endDate]);

  const handlePageChange = (page: number) => {
    setCurrentPage(page);
    loadDnsLogs(page);
  };

  const clearFilters = () => {
    setSearchTerm('');
    setActionFilter('');
    setGroupFilter('');
    setStartDate('');
    setEndDate('');
    setCurrentPage(1);
  };

  const getActionBadgeVariant = (action: string) => {
    switch (action) {
      case 'added': return 'success';
      case 'processed': return 'info';
      case 'skipped': return 'secondary';
      case 'error': return 'danger';
      default: return 'primary';
    }
  };

  const formatDateTime = (dateString: string) => {
    return new Date(dateString).toLocaleString();
  };

  const renderPagination = () => {
    if (totalPages <= 1) return null;

    const items = [];
    const maxVisible = 5;
    const start = Math.max(1, currentPage - Math.floor(maxVisible / 2));
    const end = Math.min(totalPages, start + maxVisible - 1);

    // First page
    if (start > 1) {
      items.push(
        <Pagination.Item key={1} onClick={() => handlePageChange(1)}>
          1
        </Pagination.Item>
      );
      if (start > 2) {
        items.push(<Pagination.Ellipsis key="ellipsis-start" />);
      }
    }

    // Page range
    for (let page = start; page <= end; page++) {
      items.push(
        <Pagination.Item
          key={page}
          active={page === currentPage}
          onClick={() => handlePageChange(page)}
        >
          {page}
        </Pagination.Item>
      );
    }

    // Last page
    if (end < totalPages) {
      if (end < totalPages - 1) {
        items.push(<Pagination.Ellipsis key="ellipsis-end" />);
      }
      items.push(
        <Pagination.Item key={totalPages} onClick={() => handlePageChange(totalPages)}>
          {totalPages}
        </Pagination.Item>
      );
    }

    return (
      <div className="d-flex justify-content-center mt-3">
        <Pagination>
          <Pagination.Prev 
            disabled={currentPage === 1}
            onClick={() => handlePageChange(currentPage - 1)}
          />
          {items}
          <Pagination.Next 
            disabled={currentPage === totalPages}
            onClick={() => handlePageChange(currentPage + 1)}
          />
        </Pagination>
      </div>
    );
  };

  if (loading && !logs.length) {
    return (
      <div className="text-center py-5">
        <div className="loading-spinner me-2"></div>
        Loading DNS logs...
      </div>
    );
  }

  return (
    <div className="fade-in">
      <Row>
        <Col>
          <div className="d-flex justify-content-between align-items-center mb-4">
            <h1>
              <i className="fas fa-file-alt me-2"></i>
              DNS Processing Logs
            </h1>
            <div className="d-flex align-items-center">
              <div className="me-3">
                <small className="text-muted">
                  Total: <Badge bg="primary">{totalCount}</Badge>
                  {stats && (
                    <>
                      {' '}Last 24h: <Badge bg="info">{stats.statistics.recent_24h}</Badge>
                    </>
                  )}
                </small>
              </div>
              <Button variant="outline-primary" size="sm" onClick={() => loadDnsLogs(currentPage)} disabled={loading}>
                <i className="fas fa-refresh me-1"></i>
                {loading ? 'Loading...' : 'Refresh'}
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

      {/* Statistics Cards */}
      {stats && (
        <Row className="mb-4">
          <Col md={3}>
            <Card className="h-100">
              <Card.Body className="text-center">
                <i className="fas fa-list fa-2x text-primary mb-2"></i>
                <h4 className="mb-1">{stats.statistics.total_logs}</h4>
                <small className="text-muted">Total Logs</small>
              </Card.Body>
            </Card>
          </Col>
          <Col md={3}>
            <Card className="h-100">
              <Card.Body className="text-center">
                <i className="fas fa-route fa-2x text-success mb-2"></i>
                <h4 className="mb-1">{stats.statistics.total_routes_processed}</h4>
                <small className="text-muted">Routes Processed</small>
              </Card.Body>
            </Card>
          </Col>
          <Col md={3}>
            <Card className="h-100">
              <Card.Body className="text-center">
                <i className="fas fa-clock fa-2x text-info mb-2"></i>
                <h4 className="mb-1">{stats.statistics.recent_24h}</h4>
                <small className="text-muted">Last 24 Hours</small>
              </Card.Body>
            </Card>
          </Col>
          <Col md={3}>
            <Card className="h-100">
              <Card.Body className="text-center">
                <i className="fas fa-layer-group fa-2x text-warning mb-2"></i>
                <h4 className="mb-1">{Object.keys(stats.statistics.by_group).length}</h4>
                <small className="text-muted">Active Groups</small>
              </Card.Body>
            </Card>
          </Col>
        </Row>
      )}

      {/* Filter Section */}
      <Row className="mb-4">
        <Col>
          <Card>
            <Card.Body>
              <Row className="align-items-end">
                <Col md={4}>
                  <Form.Group>
                    <Form.Label>Search</Form.Label>
                    <div className="input-group">
                      <span className="input-group-text">
                        <i className="fas fa-search"></i>
                      </span>
                      <Form.Control
                        type="text"
                        placeholder="Search domains, groups, or comments..."
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                      />
                    </div>
                  </Form.Group>
                </Col>
                <Col md={2}>
                  <Form.Group>
                    <Form.Label>Action</Form.Label>
                    <Form.Select
                      value={actionFilter}
                      onChange={(e) => setActionFilter(e.target.value)}
                    >
                      <option value="">All Actions</option>
                      <option value="processed">Processed</option>
                      <option value="added">Added</option>
                      <option value="skipped">Skipped</option>
                      <option value="error">Error</option>
                    </Form.Select>
                  </Form.Group>
                </Col>
                <Col md={2}>
                  <Form.Group>
                    <Form.Label>Group</Form.Label>
                    <Form.Select
                      value={groupFilter}
                      onChange={(e) => setGroupFilter(e.target.value)}
                    >
                      <option value="">All Groups</option>
                      {availableGroups.map(group => (
                        <option key={group} value={group}>{group}</option>
                      ))}
                    </Form.Select>
                  </Form.Group>
                </Col>
                <Col md={2}>
                  <Form.Group>
                    <Form.Label>Start Date</Form.Label>
                    <Form.Control
                      type="datetime-local"
                      value={startDate}
                      onChange={(e) => setStartDate(e.target.value)}
                    />
                  </Form.Group>
                </Col>
                <Col md={2}>
                  <Form.Group>
                    <Form.Label>End Date</Form.Label>
                    <Form.Control
                      type="datetime-local"
                      value={endDate}
                      onChange={(e) => setEndDate(e.target.value)}
                    />
                  </Form.Group>
                </Col>
              </Row>
              <Row className="mt-3">
                <Col>
                  <Button variant="outline-secondary" size="sm" onClick={clearFilters}>
                    <i className="fas fa-times me-1"></i>
                    Clear Filters
                  </Button>
                </Col>
              </Row>
            </Card.Body>
          </Card>
        </Col>
      </Row>

      {/* Logs Table */}
      <Row>
        <Col>
          <Card>
            <Card.Header>
              <div className="d-flex justify-content-between align-items-center">
                <h6 className="mb-0">
                  <i className="fas fa-table me-2"></i>
                  DNS Processing Logs
                </h6>
                <small className="text-muted">
                  Page {currentPage} of {totalPages} ({totalCount} total)
                </small>
              </div>
            </Card.Header>
            <Card.Body className="p-0">
              <div className="table-responsive">
                <Table hover className="mb-0">
                  <thead className="table-light">
                    <tr>
                      <th style={{ width: '80px' }}>Action</th>
                      <th>Domain</th>
                      <th style={{ width: '120px' }}>Group</th>
                      <th style={{ width: '80px' }}>Routes</th>
                      <th style={{ width: '100px' }}>Network</th>
                      <th>IP Addresses</th>
                      <th style={{ width: '160px' }}>Time</th>
                    </tr>
                  </thead>
                  <tbody>
                    {logs.length === 0 ? (
                      <tr>
                        <td colSpan={7} className="text-center py-4">
                          {loading ? (
                            <>
                              <div className="loading-spinner me-2"></div>
                              Loading logs...
                            </>
                          ) : (
                            <>
                              <i className="fas fa-file-alt fa-2x text-muted mb-3"></i>
                              <h6 className="text-muted">No DNS logs found</h6>
                              <p className="text-muted mb-0">
                                {searchTerm || actionFilter || groupFilter || startDate || endDate
                                  ? 'Try adjusting your search terms or filters'
                                  : 'DNS processing logs will appear here when DNS requests are processed'}
                              </p>
                            </>
                          )}
                        </td>
                      </tr>
                    ) : (
                      logs.map((log) => (
                        <tr key={log.id}>
                          <td>
                            <Badge bg={getActionBadgeVariant(log.action)}>
                              {log.action}
                            </Badge>
                          </td>
                          <td>
                            <code className="text-primary">{log.domain}</code>
                          </td>
                          <td>
                            <Badge bg="outline-secondary" className="border">
                              {log.group_name}
                            </Badge>
                          </td>
                          <td className="text-center">
                            {log.routes_count > 0 ? (
                              <Badge bg="info">{log.routes_count}</Badge>
                            ) : (
                              <span className="text-muted">-</span>
                            )}
                          </td>
                          <td>
                            {log.network ? (
                              <small>
                                <code className="text-secondary">{log.network}/{log.mask}</code>
                              </small>
                            ) : (
                              <span className="text-muted">-</span>
                            )}
                          </td>
                          <td>
                            {log.ip_addresses.length > 0 ? (
                              <div>
                                {log.ip_addresses.slice(0, 2).map((ip, idx) => (
                                  <small key={idx} className="d-block">
                                    <code className="text-success">{ip}</code>
                                  </small>
                                ))}
                                {log.ip_addresses.length > 2 && (
                                  <small className="text-muted">
                                    +{log.ip_addresses.length - 2} more
                                  </small>
                                )}
                              </div>
                            ) : (
                              <span className="text-muted">-</span>
                            )}
                          </td>
                          <td>
                            <small className="text-muted">
                              {formatDateTime(log.created_at)}
                            </small>
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </Table>
              </div>
            </Card.Body>
          </Card>
          
          {renderPagination()}
        </Col>
      </Row>
    </div>
  );
};

export default DnsLogs;
