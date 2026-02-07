import React, { useState } from 'react';
import { Card, Row, Col, Button, Alert, Badge, Form } from 'react-bootstrap';
import { apiService } from '../services/api';
import { useNotification } from '../contexts/NotificationContext';

const DumpImport: React.FC = () => {
  const { showNotification } = useNotification();
  const [loading, setLoading] = useState<{ [key: string]: boolean }>({});
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [databaseDump, setDatabaseDump] = useState<string>('');
  const [routerRoutesDump, setRouterRoutesDump] = useState<string>('');
  const [clearDatabase, setClearDatabase] = useState(false);

  const setLoadingState = (key: string, value: boolean) => {
    setLoading(prev => ({ ...prev, [key]: value }));
  };

  const handleDumpDatabase = async () => {
    try {
      setLoadingState('dumpDatabase', true);
      setError(null);
      setSuccess(null);

      const dump = await apiService.dumpDatabase();
      const jsonString = JSON.stringify(dump, null, 2);
      setDatabaseDump(jsonString);
      setSuccess('Database dump downloaded successfully');
      showNotification('success', 'Database dump downloaded successfully');
    } catch (err: any) {
      const errorMsg = err.response?.data?.error || err.message || 'Failed to dump database';
      setError(errorMsg);
      showNotification('error', errorMsg);
    } finally {
      setLoadingState('dumpDatabase', false);
    }
  };

  const handleDownloadDatabaseDump = () => {
    if (!databaseDump) {
      showNotification('warning', 'Please dump database first');
      return;
    }

    const blob = new Blob([databaseDump], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `database-dump-${new Date().toISOString().split('T')[0]}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    showNotification('success', 'Database dump file downloaded');
  };

  const handleImportDatabase = async () => {
    if (!databaseDump.trim()) {
      setError('Please paste database dump JSON or dump database first');
      showNotification('warning', 'Please provide database dump data');
      return;
    }

    try {
      setLoadingState('importDatabase', true);
      setError(null);
      setSuccess(null);

      const dumpData = JSON.parse(databaseDump);
      const result = await apiService.importDatabase(dumpData, clearDatabase);

      setSuccess(`Database imported successfully: ${result.imported.groups} groups, ${result.imported.domains} domains`);
      showNotification('success', 'Database imported successfully');
      setDatabaseDump('');
    } catch (err: any) {
      let errorMsg = 'Failed to import database';
      if (err.response?.data?.error) {
        errorMsg = err.response.data.error;
      } else if (err instanceof SyntaxError) {
        errorMsg = 'Invalid JSON format';
      } else {
        errorMsg = err.message || errorMsg;
      }
      setError(errorMsg);
      showNotification('error', errorMsg);
    } finally {
      setLoadingState('importDatabase', false);
    }
  };

  const handleDumpRouterRoutes = async () => {
    try {
      setLoadingState('dumpRouterRoutes', true);
      setError(null);
      setSuccess(null);

      const dump = await apiService.dumpRouterRoutes();
      const jsonString = JSON.stringify(dump, null, 2);
      setRouterRoutesDump(jsonString);
      setSuccess(`Router routes dump downloaded successfully (${dump.routes?.length || 0} routes)`);
      showNotification('success', 'Router routes dump downloaded successfully');
    } catch (err: any) {
      const errorMsg = err.response?.data?.error || err.message || 'Failed to dump router routes';
      setError(errorMsg);
      showNotification('error', errorMsg);
    } finally {
      setLoadingState('dumpRouterRoutes', false);
    }
  };

  const handleDownloadRouterRoutesDump = () => {
    if (!routerRoutesDump) {
      showNotification('warning', 'Please dump router routes first');
      return;
    }

    const blob = new Blob([routerRoutesDump], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `router-routes-dump-${new Date().toISOString().split('T')[0]}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    showNotification('success', 'Router routes dump file downloaded');
  };

  const handleImportRouterRoutes = async () => {
    if (!routerRoutesDump.trim()) {
      setError('Please paste router routes dump JSON or dump router routes first');
      showNotification('warning', 'Please provide router routes dump data');
      return;
    }

    try {
      setLoadingState('importRouterRoutes', true);
      setError(null);
      setSuccess(null);

      const dumpData = JSON.parse(routerRoutesDump);
      const result = await apiService.importRouterRoutes(dumpData);

      setSuccess(`Router routes imported successfully: ${result.imported} routes`);
      showNotification('success', 'Router routes imported successfully');
      setRouterRoutesDump('');
    } catch (err: any) {
      let errorMsg = 'Failed to import router routes';
      if (err.response?.data?.error) {
        errorMsg = err.response.data.error;
      } else if (err instanceof SyntaxError) {
        errorMsg = 'Invalid JSON format';
      } else {
        errorMsg = err.message || errorMsg;
      }
      setError(errorMsg);
      showNotification('error', errorMsg);
    } finally {
      setLoadingState('importRouterRoutes', false);
    }
  };

  return (
    <>
      <Row>
        <Col>
          <div className="page-header">
            <h1>Dump & Import</h1>
            <p className="text-muted">Export and import database and router routes</p>
          </div>
        </Col>
      </Row>

      {error && (
        <Alert variant="danger" dismissible onClose={() => setError(null)}>
          <i className="fas fa-exclamation-triangle me-2"></i>
          {error}
        </Alert>
      )}

      {success && (
        <Alert variant="success" dismissible onClose={() => setSuccess(null)}>
          <i className="fas fa-check-circle me-2"></i>
          {success}
        </Alert>
      )}

      {/* Database Dump/Import Section */}
      <Row className="mb-4">
        <Col>
          <Card>
            <Card.Header>
              <h5 className="mb-0">
                <i className="fas fa-database me-2"></i>
                Database Dump & Import
              </h5>
            </Card.Header>
            <Card.Body>
              <Row className="mb-3">
                <Col>
                  <div className="d-flex gap-2 flex-wrap">
                    <Button
                      variant="primary"
                      onClick={handleDumpDatabase}
                      disabled={loading.dumpDatabase}
                    >
                      <i className="fas fa-download me-2"></i>
                      {loading.dumpDatabase ? 'Dumping...' : 'Dump Database'}
                    </Button>
                    {databaseDump && (
                      <Button
                        variant="outline-primary"
                        onClick={handleDownloadDatabaseDump}
                      >
                        <i className="fas fa-file-download me-2"></i>
                        Download as File
                      </Button>
                    )}
                  </div>
                </Col>
              </Row>

              <Form.Group className="mb-3">
                <Form.Label>Database Dump JSON</Form.Label>
                <Form.Control
                  as="textarea"
                  rows={10}
                  value={databaseDump}
                  onChange={(e) => setDatabaseDump(e.target.value)}
                  placeholder="Paste database dump JSON here or dump database first..."
                  style={{ fontFamily: 'monospace', fontSize: '0.875rem' }}
                />
                <Form.Text className="text-muted">
                  Paste a database dump JSON to import, or dump the current database first
                </Form.Text>
              </Form.Group>

              <Form.Group className="mb-3">
                <Form.Check
                  type="checkbox"
                  label="Clear existing data before import"
                  checked={clearDatabase}
                  onChange={(e) => setClearDatabase(e.target.checked)}
                />
                <Form.Text className="text-muted">
                  If checked, all existing domain groups and domains will be deleted before import
                </Form.Text>
              </Form.Group>

              <Button
                variant="success"
                onClick={handleImportDatabase}
                disabled={loading.importDatabase || !databaseDump.trim()}
              >
                <i className="fas fa-upload me-2"></i>
                {loading.importDatabase ? 'Importing...' : 'Import Database'}
              </Button>
            </Card.Body>
          </Card>
        </Col>
      </Row>

      {/* Router Routes Dump/Import Section */}
      <Row className="mb-4">
        <Col>
          <Card>
            <Card.Header>
              <h5 className="mb-0">
                <i className="fas fa-router me-2"></i>
                Router Routes Dump & Import
              </h5>
            </Card.Header>
            <Card.Body>
              <Row className="mb-3">
                <Col>
                  <div className="d-flex gap-2 flex-wrap">
                    <Button
                      variant="primary"
                      onClick={handleDumpRouterRoutes}
                      disabled={loading.dumpRouterRoutes}
                    >
                      <i className="fas fa-download me-2"></i>
                      {loading.dumpRouterRoutes ? 'Dumping...' : 'Dump Router Routes'}
                    </Button>
                    {routerRoutesDump && (
                      <Button
                        variant="outline-primary"
                        onClick={handleDownloadRouterRoutesDump}
                      >
                        <i className="fas fa-file-download me-2"></i>
                        Download as File
                      </Button>
                    )}
                  </div>
                </Col>
              </Row>

              <Form.Group className="mb-3">
                <Form.Label>Router Routes Dump JSON</Form.Label>
                <Form.Control
                  as="textarea"
                  rows={10}
                  value={routerRoutesDump}
                  onChange={(e) => setRouterRoutesDump(e.target.value)}
                  placeholder="Paste router routes dump JSON here or dump router routes first..."
                  style={{ fontFamily: 'monospace', fontSize: '0.875rem' }}
                />
                <Form.Text className="text-muted">
                  Paste a router routes dump JSON to import, or dump the current router routes first
                </Form.Text>
              </Form.Group>

              <Alert variant="warning">
                <i className="fas fa-exclamation-triangle me-2"></i>
                <strong>Warning:</strong> Importing router routes will add routes to the router. Make sure the routes are valid and compatible with your router configuration.
              </Alert>

              <Button
                variant="success"
                onClick={handleImportRouterRoutes}
                disabled={loading.importRouterRoutes || !routerRoutesDump.trim()}
              >
                <i className="fas fa-upload me-2"></i>
                {loading.importRouterRoutes ? 'Importing...' : 'Import Router Routes'}
              </Button>
            </Card.Body>
          </Card>
        </Col>
      </Row>
    </>
  );
};

export default DumpImport;

