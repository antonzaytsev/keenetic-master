import React, { useState, useEffect } from 'react';
import { Card, Row, Col, Form, Button, Alert, Badge, FloatingLabel } from 'react-bootstrap';
import { useNavigate, useParams } from 'react-router-dom';
import { apiService } from '../services/api';
import { useNotification } from '../contexts/NotificationContext';

interface GroupFormData {
  name: string;
  mask: string;
  interfaces: string;
  domains: string[];
  follow_dns: string[];
}

interface GroupFormProps {
  mode: 'add' | 'edit';
}

const GroupForm: React.FC<GroupFormProps> = ({ mode }) => {
  const navigate = useNavigate();
  const { groupName } = useParams<{ groupName: string }>();
  const { showNotification } = useNotification();
  
  const [formData, setFormData] = useState<GroupFormData>({
    name: '',
    mask: '',
    interfaces: '',
    domains: [],
    follow_dns: []
  });
  
  const [domainsText, setDomainsText] = useState('');
  const [followDnsText, setFollowDnsText] = useState('');
  const [loading, setLoading] = useState(false);
  const [loadingGroup, setLoadingGroup] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Load existing group data when editing
  useEffect(() => {
    if (mode === 'edit' && groupName) {
      loadGroupData();
    }
  }, [mode, groupName]);

  const loadGroupData = async () => {
    try {
      setLoadingGroup(true);
      setError(null);

      const groupData = await apiService.getDomainGroup(groupName!);

      // Convert the group data to our form format
      const domains: string[] = [];
      const followDns: string[] = [];

      if (Array.isArray(groupData)) {
        // Simple array format - all are regular domains
        domains.push(...groupData);
      } else if (typeof groupData === 'object') {
        // Hash format
        if (groupData.domains) {
          domains.push(...groupData.domains);
        }
        if (groupData.follow_dns) {
          followDns.push(...groupData.follow_dns);
        }

        setFormData(prev => ({
          ...prev,
          name: groupName!,
          mask: groupData.settings?.mask || '',
          interfaces: groupData.settings?.interfaces || ''
        }));
      }

      setDomainsText(domains.join('\n'));
      setFollowDnsText(followDns.join('\n'));

      setFormData(prev => ({
        ...prev,
        name: groupName!,
        domains,
        follow_dns: followDns
      }));

    } catch (err: any) {
      console.error('Failed to load group data:', err);
      setError(`Failed to load group data: ${err.response?.data?.error || err.message}`);
    } finally {
      setLoadingGroup(false);
    }
  };

  const handleInputChange = (field: keyof GroupFormData, value: string) => {
    setFormData(prev => ({
      ...prev,
      [field]: value
    }));
    setError(null);
  };

  const handleDomainsChange = (value: string) => {
    setDomainsText(value);
    const domains = value.split('\n')
      .map(d => d.trim())
      .filter(d => d.length > 0);
    setFormData(prev => ({ ...prev, domains }));
    setError(null);
  };

  const handleFollowDnsChange = (value: string) => {
    setFollowDnsText(value);
    const followDns = value.split('\n')
      .map(d => d.trim())
      .filter(d => d.length > 0);
    setFormData(prev => ({ ...prev, follow_dns: followDns }));
    setError(null);
  };

  const validateForm = (): string | null => {
    if (!formData.name.trim()) {
      return 'Group name is required';
    }

    if (formData.name.includes(' ') || formData.name.includes('/')) {
      return 'Group name cannot contain spaces or forward slashes';
    }

    if (formData.domains.length === 0 && formData.follow_dns.length === 0) {
      return 'At least one domain is required (either regular or follow DNS)';
    }

    // Validate domain formats
    const allDomains = [...formData.domains, ...formData.follow_dns];
    for (const domain of allDomains) {
      if (domain.includes(' ')) {
        return `Invalid domain format: "${domain}" - domains cannot contain spaces`;
      }
    }

    return null;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    const validationError = validateForm();
    if (validationError) {
      setError(validationError);
      return;
    }

    try {
      setLoading(true);
      setError(null);

      // Prepare data for API
      let apiData: any = {};

      // Add settings if we have mask or interfaces
      if (formData.mask || formData.interfaces) {
        apiData.settings = {};
        if (formData.mask) apiData.settings.mask = formData.mask;
        if (formData.interfaces) apiData.settings.interfaces = formData.interfaces;
      }

      // Add domains
      if (formData.domains.length > 0) {
        if (Object.keys(apiData).length === 0) {
          // Simple array format if no settings
          apiData = formData.domains;
        } else {
          apiData.domains = formData.domains;
        }
      }

      // Add follow_dns
      if (formData.follow_dns.length > 0) {
        if (Array.isArray(apiData)) {
          // Convert to hash format
          const domains = apiData;
          apiData = { domains };
        }
        apiData.follow_dns = formData.follow_dns;
      }

      if (mode === 'add') {
        await apiService.createDomainGroup(formData.name, apiData);
        showNotification('success', `Domain group "${formData.name}" created successfully!`);
        navigate(`/groups/${formData.name}`);
      } else {
        await apiService.updateDomainGroup(formData.name, apiData);
        showNotification('success', `Domain group "${formData.name}" updated successfully!`);
        navigate(`/groups/${formData.name}`);
      }

    } catch (err: any) {
      console.error(`Failed to ${mode} group:`, err);
      const errorMessage = err.response?.data?.error || err.message;
      setError(`Failed to ${mode} group: ${errorMessage}`);
      showNotification('error', `Failed to ${mode} group: ${errorMessage}`);
    } finally {
      setLoading(false);
    }
  };

  const handleCancel = () => {
    navigate(-1);
  };

  if (mode === 'edit' && loadingGroup) {
    return (
      <div className="text-center py-5">
        <div className="loading-spinner me-2"></div>
        Loading group data...
      </div>
    );
  }

  return (
    <>
      <Row>
        <Col>
          <div className="d-flex justify-content-between align-items-center mb-4">
            <h1>
              <i className={`fas ${mode === 'add' ? 'fa-plus' : 'fa-edit'} me-2`}></i>
              {mode === 'add' ? 'Add Domain Group' : `Edit Domain Group: ${formData.name}`}
            </h1>
            <Button variant="outline-secondary" onClick={handleCancel}>
              <i className="fas fa-arrow-left me-1"></i>
              Back
            </Button>
          </div>
        </Col>
      </Row>

      {error && (
        <Alert variant="danger" dismissible onClose={() => setError(null)}>
          <i className="fas fa-exclamation-triangle me-2"></i>
          {error}
        </Alert>
      )}

      <Row>
        <Col lg={8} xl={6}>
          <Card>
            <Card.Header>
              <h6 className="mb-0">
                <i className="fas fa-layer-group me-2"></i>
                {mode === 'add' ? 'New Group Configuration' : 'Edit Group Configuration'}
              </h6>
            </Card.Header>
            <Card.Body>
              <Form onSubmit={handleSubmit}>
                <Row className="mb-3">
                  <Col>
                    <FloatingLabel label="Group Name" className="mb-3">
                      <Form.Control
                        type="text"
                        placeholder="Group Name"
                        value={formData.name}
                        onChange={(e) => handleInputChange('name', e.target.value)}
                        required
                        disabled={mode === 'edit'}
                      />
                      <Form.Text className="text-muted">
                        {mode === 'add' ? 'Enter a unique name for this group (no spaces or slashes)' : 'Group name cannot be changed'}
                      </Form.Text>
                    </FloatingLabel>
                  </Col>
                </Row>

                <Row className="mb-3">
                  <Col md={6}>
                    <FloatingLabel label="Network Mask (Optional)" className="mb-3">
                      <Form.Control
                        type="text"
                        placeholder="Network Mask"
                        value={formData.mask}
                        onChange={(e) => handleInputChange('mask', e.target.value)}
                      />
                      <Form.Text className="text-muted">
                        e.g., 255.255.255.0 or 24
                      </Form.Text>
                    </FloatingLabel>
                  </Col>
                  <Col md={6}>
                    <FloatingLabel label="Interfaces (Optional)" className="mb-3">
                      <Form.Control
                        type="text"
                        placeholder="Interfaces"
                        value={formData.interfaces}
                        onChange={(e) => handleInputChange('interfaces', e.target.value)}
                      />
                      <Form.Text className="text-muted">
                        e.g., ISP,VPN or single interface
                      </Form.Text>
                    </FloatingLabel>
                  </Col>
                </Row>

                <Row className="mb-3">
                  <Col>
                    <Form.Label>
                      <i className="fas fa-globe me-2"></i>
                      Regular Domains
                      {formData.domains.length > 0 && (
                        <Badge bg="primary" className="ms-2">{formData.domains.length}</Badge>
                      )}
                    </Form.Label>
                    <Form.Control
                      as="textarea"
                      rows={8}
                      placeholder="Enter domains, one per line&#10;example.com&#10;subdomain.example.com&#10;*.wildcard.com"
                      value={domainsText}
                      onChange={(e) => handleDomainsChange(e.target.value)}
                    />
                    <Form.Text className="text-muted">
                      Enter regular domains that will have their IP addresses resolved and added to routing
                    </Form.Text>
                  </Col>
                </Row>

                <Row className="mb-4">
                  <Col>
                    <Form.Label>
                      <i className="fas fa-eye me-2"></i>
                      Follow DNS Domains
                      {formData.follow_dns.length > 0 && (
                        <Badge bg="success" className="ms-2">{formData.follow_dns.length}</Badge>
                      )}
                    </Form.Label>
                    <Form.Control
                      as="textarea"
                      rows={6}
                      placeholder="Enter domains to monitor via DNS logs, one per line&#10;monitored.example.com&#10;tracked.service.com"
                      value={followDnsText}
                      onChange={(e) => handleFollowDnsChange(e.target.value)}
                    />
                    <Form.Text className="text-muted">
                      These domains will be monitored through DNS logs and automatically added to routing when accessed
                    </Form.Text>
                  </Col>
                </Row>

                <div className="d-grid gap-2 d-md-flex justify-content-md-end">
                  <Button variant="secondary" onClick={handleCancel} disabled={loading}>
                    <i className="fas fa-times me-1"></i>
                    Cancel
                  </Button>
                  <Button type="submit" variant="primary" disabled={loading}>
                    {loading && <span className="loading-spinner me-2" style={{width: '1rem', height: '1rem'}}></span>}
                    <i className={`fas ${loading ? 'fa-spinner fa-spin' : mode === 'add' ? 'fa-plus' : 'fa-save'} me-1`}></i>
                    {loading ? 'Saving...' : mode === 'add' ? 'Create Group' : 'Update Group'}
                  </Button>
                </div>
              </Form>
            </Card.Body>
          </Card>
        </Col>
        <Col lg={4} xl={6}>
          <Card className="mt-4 mt-lg-0">
            <Card.Header>
              <h6 className="mb-0">
                <i className="fas fa-info-circle me-2"></i>
                Configuration Help
              </h6>
            </Card.Header>
            <Card.Body>
              <div className="mb-3">
                <h6><i className="fas fa-layer-group me-2 text-primary"></i>Group Name</h6>
                <p className="small text-muted">
                  Must be unique and cannot contain spaces or forward slashes. This name will be used
                  to identify the group in routing rules and logs.
                </p>
              </div>

              <div className="mb-3">
                <h6><i className="fas fa-globe me-2 text-success"></i>Regular Domains</h6>
                <p className="small text-muted">
                  These domains will have their IP addresses resolved immediately and added to the routing table.
                  Supports wildcards (*.example.com) and subdomains.
                </p>
              </div>

              <div className="mb-3">
                <h6><i className="fas fa-eye me-2 text-warning"></i>Follow DNS Domains</h6>
                <p className="small text-muted">
                  These domains will be monitored through DNS request logs. When a request is made to
                  these domains, their IPs will be automatically resolved and added to routing.
                </p>
              </div>

              <div className="mb-3">
                <h6><i className="fas fa-network-wired me-2 text-info"></i>Network Settings</h6>
                <p className="small text-muted">
                  <strong>Mask:</strong> Optional subnet mask for all routes in this group.<br/>
                  <strong>Interfaces:</strong> Optional comma-separated list of network interfaces to use.
                </p>
              </div>
            </Card.Body>
          </Card>
        </Col>
      </Row>
    </>
  );
};

export default GroupForm;
