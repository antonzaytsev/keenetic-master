import React, { useState, useEffect } from 'react';
import { Card, Row, Col, Button, Alert, Form, Spinner, InputGroup } from 'react-bootstrap';
import { apiService } from '../services/api';
import { useNotification } from '../contexts/NotificationContext';

interface SettingValue {
  value: string | null;
  description: string;
  updated_at: string | null;
}

interface SettingsData {
  keenetic_login: SettingValue;
  keenetic_password: SettingValue;
  keenetic_host: SettingValue;
  keenetic_vpn_interface: SettingValue;
}

interface RouterInterface {
  id: string;
  description: string;
  name: string;
}

const Settings: React.FC = () => {
  const { showNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [testing, setTesting] = useState(false);
  const [loadingInterfaces, setLoadingInterfaces] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [showPassword, setShowPassword] = useState(false);
  const [interfaces, setInterfaces] = useState<RouterInterface[]>([]);
  
  const [formData, setFormData] = useState({
    keenetic_login: '',
    keenetic_password: '',
    keenetic_host: '',
    keenetic_vpn_interface: ''
  });

  const [originalData, setOriginalData] = useState({
    keenetic_login: '',
    keenetic_password: '',
    keenetic_host: '',
    keenetic_vpn_interface: ''
  });

  useEffect(() => {
    loadSettings();
  }, []);

  useEffect(() => {
    loadInterfaces();
  }, []);

  const loadInterfaces = async () => {
    try {
      setLoadingInterfaces(true);
      const response = await apiService.getRouterInterfaces();
      if (response.success && response.interfaces) {
        setInterfaces(response.interfaces);
      }
    } catch (err: any) {
      console.warn('Could not load router interfaces:', err.message);
    } finally {
      setLoadingInterfaces(false);
    }
  };

  const loadSettings = async () => {
    try {
      setLoading(true);
      setError(null);
      
      const response = await apiService.getSettings();
      const settings: SettingsData = response.settings;
      
      const newFormData = {
        keenetic_login: settings.keenetic_login?.value || '',
        keenetic_password: settings.keenetic_password?.value || '',
        keenetic_host: settings.keenetic_host?.value || '',
        keenetic_vpn_interface: settings.keenetic_vpn_interface?.value || ''
      };
      
      setFormData(newFormData);
      setOriginalData(newFormData);
    } catch (err: any) {
      const errorMsg = err.response?.data?.error || err.message || 'Failed to load settings';
      setError(errorMsg);
      showNotification('error', errorMsg);
    } finally {
      setLoading(false);
    }
  };

  const handleInputChange = (field: string, value: string) => {
    setFormData(prev => ({ ...prev, [field]: value }));
  };


  const hasChanges = () => {
    return Object.keys(formData).some(
      key => formData[key as keyof typeof formData] !== originalData[key as keyof typeof originalData]
    );
  };

  const handleSave = async () => {
    try {
      setSaving(true);
      setError(null);
      setSuccess(null);

      await apiService.updateSettings(formData);
      
      setOriginalData({ ...formData });
      setSuccess('Settings saved successfully');
      showNotification('success', 'Settings saved successfully');
    } catch (err: any) {
      const errorMsg = err.response?.data?.error || err.message || 'Failed to save settings';
      setError(errorMsg);
      showNotification('error', errorMsg);
    } finally {
      setSaving(false);
    }
  };

  const handleTestConnection = async () => {
    try {
      setTesting(true);
      setError(null);
      setSuccess(null);

      const response = await apiService.testConnection();
      
      if (response.success) {
        setSuccess(`Connection successful! Found ${response.interface_count} interfaces on router.`);
        showNotification('success', 'Connection to router successful');
      } else {
        setError(response.message || 'Connection failed');
        showNotification('error', response.message || 'Connection failed');
      }
    } catch (err: any) {
      const errorMsg = err.response?.data?.message || err.response?.data?.error || err.message || 'Connection test failed';
      setError(errorMsg);
      showNotification('error', errorMsg);
    } finally {
      setTesting(false);
    }
  };

  const handleReset = () => {
    setFormData({ ...originalData });
    setError(null);
    setSuccess(null);
  };

  if (loading) {
    return (
      <div className="d-flex justify-content-center align-items-center" style={{ minHeight: '400px' }}>
        <Spinner animation="border" role="status">
          <span className="visually-hidden">Loading...</span>
        </Spinner>
      </div>
    );
  }

  return (
    <>
      <Row>
        <Col>
          <div className="page-header">
            <h1>Settings</h1>
            <p className="text-muted">Configure Keenetic router connection settings</p>
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

      <Row className="mb-4">
        <Col lg={8}>
          <Card>
            <Card.Header>
              <h5 className="mb-0">
                <i className="fas fa-router me-2"></i>
                Router Connection
              </h5>
            </Card.Header>
            <Card.Body>
              <Form>
                <Form.Group className="mb-3">
                  <Form.Label>Router Host</Form.Label>
                  <Form.Control
                    type="text"
                    value={formData.keenetic_host}
                    onChange={(e) => handleInputChange('keenetic_host', e.target.value)}
                    placeholder="e.g., 192.168.1.1 or router.local"
                  />
                  <Form.Text className="text-muted">
                    IP address or hostname of your Keenetic router
                  </Form.Text>
                </Form.Group>

                <Form.Group className="mb-3">
                  <Form.Label>Login</Form.Label>
                  <Form.Control
                    type="text"
                    value={formData.keenetic_login}
                    onChange={(e) => handleInputChange('keenetic_login', e.target.value)}
                    placeholder="Router admin username"
                  />
                  <Form.Text className="text-muted">
                    Username for router authentication
                  </Form.Text>
                </Form.Group>

                <Form.Group className="mb-3">
                  <Form.Label>Password</Form.Label>
                  <InputGroup>
                    <Form.Control
                      type={showPassword ? 'text' : 'password'}
                      value={formData.keenetic_password}
                      onChange={(e) => handleInputChange('keenetic_password', e.target.value)}
                      placeholder="Router admin password"
                    />
                    <Button
                      variant="outline-secondary"
                      onClick={() => setShowPassword(!showPassword)}
                    >
                      <i className={`fas fa-eye${showPassword ? '-slash' : ''}`}></i>
                    </Button>
                  </InputGroup>
                  <Form.Text className="text-muted">
                    Password for router authentication
                  </Form.Text>
                </Form.Group>

                <Form.Group className="mb-4">
                  <Form.Label>
                    VPN Interface
                    <Button
                      variant="link"
                      size="sm"
                      className="p-0 ms-2"
                      onClick={loadInterfaces}
                      disabled={loadingInterfaces}
                      title="Refresh interfaces from router"
                    >
                      {loadingInterfaces ? (
                        <Spinner animation="border" size="sm" />
                      ) : (
                        <i className="fas fa-sync-alt"></i>
                      )}
                    </Button>
                  </Form.Label>
                  
                  <InputGroup>
                    <Form.Select
                      value={formData.keenetic_vpn_interface}
                      onChange={(e) => handleInputChange('keenetic_vpn_interface', e.target.value)}
                      disabled={loadingInterfaces}
                    >
                      <option value="">Select an interface...</option>
                      {interfaces.map((iface) => (
                        <option key={iface.id} value={iface.id}>
                          {iface.id} {iface.description !== iface.id ? `(${iface.description})` : ''}
                        </option>
                      ))}
                      {formData.keenetic_vpn_interface && 
                       !interfaces.find(i => i.id === formData.keenetic_vpn_interface) && (
                        <option value={formData.keenetic_vpn_interface}>
                          {formData.keenetic_vpn_interface} (current)
                        </option>
                      )}
                    </Form.Select>
                  </InputGroup>
                  
                  <Form.Text className="text-muted">
                    {interfaces.length > 0 
                      ? `${interfaces.length} interfaces available. Select the default VPN interface for routing.`
                      : 'Click refresh to load interfaces from router.'}
                  </Form.Text>
                </Form.Group>

                <div className="d-flex gap-2 flex-wrap">
                  <Button
                    variant="primary"
                    onClick={handleSave}
                    disabled={saving || !hasChanges()}
                  >
                    {saving ? (
                      <>
                        <Spinner animation="border" size="sm" className="me-2" />
                        Saving...
                      </>
                    ) : (
                      <>
                        <i className="fas fa-save me-2"></i>
                        Save Settings
                      </>
                    )}
                  </Button>

                  <Button
                    variant="outline-secondary"
                    onClick={handleReset}
                    disabled={saving || !hasChanges()}
                  >
                    <i className="fas fa-undo me-2"></i>
                    Reset
                  </Button>

                  <Button
                    variant="outline-success"
                    onClick={handleTestConnection}
                    disabled={testing}
                  >
                    {testing ? (
                      <>
                        <Spinner animation="border" size="sm" className="me-2" />
                        Testing...
                      </>
                    ) : (
                      <>
                        <i className="fas fa-plug me-2"></i>
                        Test Connection
                      </>
                    )}
                  </Button>
                </div>
              </Form>
            </Card.Body>
          </Card>
        </Col>

        <Col lg={4}>
          <Card>
            <Card.Header>
              <h5 className="mb-0">
                <i className="fas fa-info-circle me-2"></i>
                Information
              </h5>
            </Card.Header>
            <Card.Body>
              <p className="text-muted mb-0" style={{ fontSize: '0.875rem' }}>
                These settings configure the connection to your Keenetic router.
                All settings are stored in the application database.
              </p>
            </Card.Body>
          </Card>

          <Card className="mt-3">
            <Card.Header>
              <h5 className="mb-0">
                <i className="fas fa-shield-alt me-2"></i>
                Security Note
              </h5>
            </Card.Header>
            <Card.Body>
              <p className="text-muted mb-0" style={{ fontSize: '0.875rem' }}>
                Credentials are stored in the application database. 
                Ensure your database is properly secured and not accessible from untrusted networks.
              </p>
            </Card.Body>
          </Card>
        </Col>
      </Row>
    </>
  );
};

export default Settings;
