import React, { useState, useEffect, useCallback } from 'react';
import { Card, Row, Col, Form, Button, Alert, Table } from 'react-bootstrap';
import { apiService, SyncStatusData, SyncLog } from '../services/api';

const SyncStatus: React.FC = () => {
  const [syncData, setSyncData] = useState<SyncStatusData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [operationFilter, setOperationFilter] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [filteredLogs, setFilteredLogs] = useState<SyncLog[]>([]);

  const loadSyncData = useCallback(async () => {
    try {
      setLoading(true);
      const data = await apiService.getSyncStats();
      setSyncData(data);
      setError(null);
    } catch (err) {
      setError(`Failed to load sync status: ${err}`);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadSyncData();
    
    // Auto-refresh every 15 seconds (more frequent for sync status)
    const interval = setInterval(() => {
      if (!operationFilter && !statusFilter) {
        loadSyncData();
      }
    }, 15000);

    return () => clearInterval(interval);
  }, [loadSyncData, operationFilter, statusFilter]);

  useEffect(() => {
    if (!syncData) return;

    let filtered = syncData.recent_logs;

    // Apply operation filter
    if (operationFilter) {
      filtered = filtered.filter(log => log.operation === operationFilter);
    }

    // Apply status filter
    if (statusFilter) {
      const isSuccess = statusFilter === 'success';
      filtered = filtered.filter(log => log.success === isSuccess);
    }

    setFilteredLogs(filtered);
  }, [operationFilter, statusFilter, syncData]);

  const formatDate = (dateString?: string) => {
    if (!dateString) return '';
    const date = new Date(dateString);
    return date.toLocaleDateString() + ' ' + date.toLocaleTimeString();
  };

  const getUniqueOperations = () => {
    if (!syncData) return [];
    const operationsSet = new Set(syncData.recent_logs.map(log => log.operation));
    const operations = Array.from(operationsSet);
    return operations.sort();
  };

  if (loading) {
    return (
      <div className="text-center py-5">
        <div className="loading-spinner me-2"></div>
        Loading sync status...
      </div>
    );
  }

  if (!syncData) {
    return (
      <Alert variant="warning">
        No sync data available
      </Alert>
    );
  }

  return (
    <div className="fade-in">
      <Row>
        <Col>
          <div className="d-flex justify-content-between align-items-center mb-4">
            <h1>
              <i className="fas fa-sync me-2"></i>
              Sync Status
            </h1>
            <div className="d-flex align-items-center">
              <Button variant="outline-primary" size="sm" onClick={loadSyncData}>
                <i className="fas fa-refresh me-1"></i>
                Refresh
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

      {/* Sync Statistics */}
      <Row className="mb-4">
        <Col md={3}>
          <Card className="text-center">
            <Card.Body>
              <i className="fas fa-network-wired fa-2x text-primary mb-2"></i>
              <h5 className="card-title">{syncData.statistics.total_routes}</h5>
              <p className="card-text text-muted">Total Routes</p>
            </Card.Body>
          </Card>
        </Col>
        <Col md={3}>
          <Card className="text-center">
            <Card.Body>
              <i className="fas fa-check-circle fa-2x text-success mb-2"></i>
              <h5 className="card-title">{syncData.statistics.synced_routes}</h5>
              <p className="card-text text-muted">Synced Routes</p>
            </Card.Body>
          </Card>
        </Col>
        <Col md={3}>
          <Card className="text-center">
            <Card.Body>
              <i className="fas fa-clock fa-2x text-warning mb-2"></i>
              <h5 className="card-title">{syncData.statistics.pending_sync}</h5>
              <p className="card-text text-muted">Pending Sync</p>
            </Card.Body>
          </Card>
        </Col>
        <Col md={3}>
          <Card className="text-center">
            <Card.Body>
              <i className="fas fa-exclamation-triangle fa-2x text-danger mb-2"></i>
              <h5 className="card-title">{syncData.statistics.stale_routes}</h5>
              <p className="card-text text-muted">Stale Routes</p>
            </Card.Body>
          </Card>
        </Col>
      </Row>

      {/* Recent Failures */}
      {syncData.recent_failures.length > 0 && (
        <Row className="mb-4">
          <Col>
            <Card className="border-danger">
              <Card.Header className="bg-danger text-white">
                <h6 className="mb-0">
                  <i className="fas fa-exclamation-triangle me-2"></i>
                  Recent Failures (Last 24 hours)
                </h6>
              </Card.Header>
              <Card.Body>
                {syncData.recent_failures.slice(0, 5).map((log, index) => (
                  <div key={log.id}>
                    <div className="d-flex justify-content-between align-items-start">
                      <div>
                        <strong>{log.operation}</strong>{' '}
                        <span className="text-muted">on</span>{' '}
                        <strong>{log.resource_type}</strong>
                        {log.resource_id && (
                          <span className="text-muted"> (ID: {log.resource_id})</span>
                        )}
                        <br />
                        <small className="text-danger">{log.error_message}</small>
                      </div>
                      <small className="text-muted">
                        <i className="fas fa-clock me-1"></i>
                        {formatDate(log.created_at)}
                      </small>
                    </div>
                    {index < Math.min(4, syncData.recent_failures.length - 1) && (
                      <hr className="my-2" />
                    )}
                  </div>
                ))}
                {syncData.recent_failures.length > 5 && (
                  <div className="text-center mt-3">
                    <small className="text-muted">
                      ... and {syncData.recent_failures.length - 5} more failures
                    </small>
                  </div>
                )}
              </Card.Body>
            </Card>
          </Col>
        </Row>
      )}

      {/* Sync Logs */}
      <Row>
        <Col>
          <Card>
            <Card.Header>
              <div className="d-flex justify-content-between align-items-center">
                <h6 className="mb-0">
                  <i className="fas fa-history me-2"></i>
                  Recent Sync Operations
                </h6>
                <div className="d-flex align-items-center">
                  <div className="me-3">
                    <Form.Select
                      size="sm"
                      value={operationFilter}
                      onChange={(e) => setOperationFilter(e.target.value)}
                    >
                      <option value="">All Operations</option>
                      {getUniqueOperations().map(op => (
                        <option key={op} value={op}>{op.toUpperCase()}</option>
                      ))}
                    </Form.Select>
                  </div>
                  <div className="me-3">
                    <Form.Select
                      size="sm"
                      value={statusFilter}
                      onChange={(e) => setStatusFilter(e.target.value)}
                    >
                      <option value="">All Statuses</option>
                      <option value="success">Success</option>
                      <option value="error">Error</option>
                    </Form.Select>
                  </div>
                  <small className="text-muted">
                    {filteredLogs.length} of {syncData.recent_logs.length} logs
                  </small>
                </div>
              </div>
            </Card.Header>
            <Card.Body className="p-0">
              {syncData.recent_logs.length === 0 ? (
                <div className="text-center py-5">
                  <i className="fas fa-history fa-3x text-muted mb-3"></i>
                  <h6 className="text-muted">No sync logs found</h6>
                  <p className="text-muted">Sync operations will appear here once they start running</p>
                </div>
              ) : (
                <div className="table-responsive">
                  <Table hover className="mb-0">
                    <thead className="table-light">
                      <tr>
                        <th>Timestamp</th>
                        <th>Operation</th>
                        <th>Resource</th>
                        <th>Status</th>
                        <th>Details</th>
                      </tr>
                    </thead>
                    <tbody>
                      {filteredLogs.length === 0 && (operationFilter || statusFilter) ? (
                        <tr>
                          <td colSpan={5} className="text-center py-4">
                            <i className="fas fa-search fa-2x text-muted mb-3"></i>
                            <h6 className="text-muted">No matching logs found</h6>
                            <p className="text-muted mb-0">Try adjusting your filters</p>
                          </td>
                        </tr>
                      ) : (
                        filteredLogs.map((log) => (
                          <tr key={log.id}>
                            <td>
                              <small className="text-muted">
                                <i className="fas fa-clock me-1"></i>
                                {formatDate(log.created_at)}
                              </small>
                            </td>
                            <td>
                              <span className="badge bg-secondary">
                                {log.operation.toUpperCase()}
                              </span>
                            </td>
                            <td>
                              <div>
                                <strong>{log.resource_type}</strong>
                                {log.resource_id && (
                                  <>
                                    <br />
                                    <small className="text-muted">ID: {log.resource_id}</small>
                                  </>
                                )}
                              </div>
                            </td>
                            <td>
                              {log.success ? (
                                <span className="status-badge status-synced">
                                  <i className="fas fa-check me-1"></i>Success
                                </span>
                              ) : (
                                <span className="status-badge status-unsynced">
                                  <i className="fas fa-times me-1"></i>Error
                                </span>
                              )}
                            </td>
                            <td>
                              {log.error_message ? (
                                <small className="text-danger">
                                  <i className="fas fa-exclamation-circle me-1"></i>
                                  {log.error_message}
                                </small>
                              ) : (
                                <small className="text-success">
                                  <i className="fas fa-check-circle me-1"></i>
                                  Operation completed successfully
                                </small>
                              )}
                            </td>
                          </tr>
                        ))
                      )}
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

export default SyncStatus;
