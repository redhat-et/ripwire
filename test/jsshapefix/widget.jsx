/**
 * JSX pin: the .jsx extension routes to the JS grammar (ingest table) and tree-sitter-javascript
 * parses JSX natively — but the webpack corpus's four .jsx files were all one-line string
 * exports, so real-corpus validation could not exercise it. This fixture does.
 */
export function WidgetPanel({ items }) {
	return (
		<ul className="widget-panel">
			{items.map(item => (
				<li key={item.id}>{item.label}</li>
			))}
		</ul>
	);
}

export const WidgetBadge = ({ count }) => <span className="badge">{count}</span>;

export default class WidgetFrame {
	render() {
		return <WidgetPanel items={this.props.items} />;
	}
}
